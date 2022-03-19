# How to build and deploy a fast.com clone using Rust Actix and WebSockets

## Introduction

For those unfamiliar with [fast.com](https://fast.com/), go check it out! It's a dead simple speed test site created by Netflix that allows you to test your network connection speed.

In this tutorial, we will build a fast.com clone using Rust Actix, WebSockets, and a simple JavaScript client. Then we will Dockerize it and add it to the GitHub container registry to deploy it to Koyeb. By the end of this tutorial you will be able to test the performance of your network connection using your very own speed test site hosted on Koyeb.

Without further ado, let's get started!

## Prerequisites

To follow this guide, you will need:

-   A local development environment with Rust installed
-   A [GitHub account](https://github.com/) o store our Docker image on the GitHub container registry
-   A [Koyeb account](https://www.koyeb.com) to deploy and run the Rust Actix server
-   [Docker](https://docs.docker.com/get-docker/) installed on your machine
-   To have [configured Docker for use with GitHub Packages](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-docker-registry)

## Steps

To build our speed test site and deploy it on Koyeb, you will need to follow these steps:

-   [Getting Started](#getting-started)
-   [A Basic Web Server with Actix](#a-basic-web-server-with-actix)
-   [Working with WebSockets using Actix](#working-with-websockets-using-actix)
-   [Sending The Test File](#sending-the-test-file)
-   [Creating The Speed Test Client](#creating-the-speed-test-client)
-   [Deploying to Koyeb](#deploying-to-koyeb)
-   [Conclusion](#conclusion)

## Getting Started

To start, let's create a new rust project:

```bash
cargo new koyeb-fast-com
```

In the `koyeb-fast-com` directory that was just created, you should see a new `Cargo.toml` file. This file is where we will tell Rust how to build our application and what dependencies we need.

In that file, let's edit the dependencies section to look like this:

```toml
[dependencies]
actix = "0.13"
actix-codec = "0.5"
actix-files = "0.6"
actix-rt = "2"
actix-web = "4"
actix-web-actors = "4.1"
awc = "3.0.0-beta.21"
env_logger = "0.9"
futures-util = { version = "0.3.7", default-features = false, features = ["std", "sink"] }
log = "0.4"
tokio = { version = "1.13.1", features = ["full"] }
tokio-stream = "0.1.8"
```

Great! Now for our project files.

Let's make two new directories for our server source code and static files (HTML):

```bash
mkdir src static
```

Let's populate the `src` directory with the following files:

```bash
touch src/main.rs src/server.rs
```

`main.rs` will be where we initialize and run the server. `server.rs` will be where we define our server logic. Specifically, the WebSocket functionality for performing the speed test.

In the `static` directory, let's create an `index.html` file and a 10 MB file that we'll send over the network to test the connection speed:

```bash
touch static index.html
dd if=/dev/zero of=static/10mb bs=1M count=10
```

That second command is creating a file that is roughly 10 megabytes of null characters. This way, we know exactly how much data we're sending over the network for calculating the connection speed later.

Our directory structure looks like this:

```text
├── Cargo.lock
├── Cargo.toml
├── src
│   ├── main.rs
│   └── server.rs
└── static
    ├── 10mb
    └── index.html
```

Awesome! Our project is looking good. Let's start building our server.

## A Basic Web Server with Actix

Actix is a high-performance web framework for Rust. It is a framework that provides a simple, yet powerful, way to build web applications. In our case, we'll be using it for two things:

1. Serving HTML to users; This will be for the main page of our application. It is how users will start the speed test and see the results.
2. Serving test files over a WebSocket connection; This will be for performing the speed test.

In `src/main.rs`, let's create a basic web server that will serve the `index.html` file from the `static` folder:

```rust
use actix_files::NamedFile;
use actix_web::{middleware, web, App, Error, HttpServer, Responder};

// This function will get the `index.html` file to serve to the user.
async fn index() -> impl Responder {
    NamedFile::open_async("./static/index.html").await.unwrap()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));

    log::info!("starting HTTP server at http://localhost:8080");

    // Here we're creating the server and binding it to port 8080.
    HttpServer::new(|| {
        App::new()
            // "/" is the path that we want to serve the `index.html` file from.
            .service(web::resource("/").to(index))
            .wrap(middleware::Logger::default())
    })
    .workers(2)
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
```

In this case, anytime someone accesses the `/` URL, we will serve the `index.html` file from the `static` folder using the `index()` function. The `index()` function gets the file using the `NamedFile` struct and then returns it to the caller.

## Working with WebSockets using Actix

Now we're going to start working with WebSockets. We'll be using the `actix-web-actors` crate to handle them. The socket logic will have to do the following:

1. Ensure the socket is open (e.g. check if the socket was either closed by the client or if the connection was interrupted). We'll do this by pinging the client every five seconds.
2. Upon request from the client, send a 10 MB file over the socket.

3. Upon request from the client, close the socket.

So, let's start by adding all the following to `src/server.rs`:

```rust
use std::fs::File;
use std::io::BufReader;
use std::io::Read;
use std::time::{Duration, Instant};

use actix::prelude::*;
use actix_web::web::Bytes;
use actix_web_actors::ws;

const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(5);
const CLIENT_TIMEOUT: Duration = Duration::from_secs(10);

pub struct MyWebSocket {
    hb: Instant,
}

impl MyWebSocket {
    pub fn new() -> Self {
        Self { hb: Instant::now() }
    }

    // This function will run on an interval, every 5 seconds to check
    // that the connection is still alive. If it's been more than
    // 10 seconds since the last ping, we'll close the connection.
    fn hb(&self, ctx: &mut <Self as Actor>::Context) {
        ctx.run_interval(HEARTBEAT_INTERVAL, |act, ctx| {
            if Instant::now().duration_since(act.hb) > CLIENT_TIMEOUT {
                ctx.stop();
                return;
            }

            ctx.ping(b"");
        });
    }
}

impl Actor for MyWebSocket {
    type Context = ws::WebsocketContext<Self>;

    // Start the heartbeat process for this connection
    fn started(&mut self, ctx: &mut Self::Context) {
        self.hb(ctx);
    }
}


// The `StreamHandler` trait is used to handle the messages that are sent over the socket.
impl StreamHandler<Result<ws::Message, ws::ProtocolError>> for MyWebSocket {

    // The `handle()` function is where we'll determine the response
    // to the client's messages. So, for example, if we ping the client,
    // it should respond with a pong. These two messages are necessary
    // for the `hb()` function to maintain the connection status.
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            // Ping/Pong will be used to make sure the connection is still alive
            Ok(ws::Message::Ping(msg)) => {
                self.hb = Instant::now();
                ctx.pong(&msg);
            }
            Ok(ws::Message::Pong(_)) => {
                self.hb = Instant::now();
            }
            // Text will echo any text received back to the client (for now)
            Ok(ws::Message::Text(text)) => ctx.text(text),
            // Close will close the socket
            Ok(ws::Message::Close(reason)) => {
                ctx.close(reason);
                ctx.stop();
            }
            _ => ctx.stop(),
        }
    }
}
```

There's a lot going on here, so I will explain in layman's terms what this code is doing and why it's important. Sockets are a way of allowing for continuous communication between a server and a client. With sockets, the connection is kept open until either the client or the server closes it.

Each client that connects to the server has their own socket. Each socket has a context, which is a type that implements the `Actor` trait. This is where we'll be working with the socket.

But, there are issues with this model.

Specifically, how do we ensure the socket is still open (since connection interruptions can disconnect it)? That's what the `hb()` function is for. It is first initialized with the current socket's context and then runs an interval. This interval will run every 5 seconds and will ping the client. If the client doesn't respond within 10 seconds, the socket will be closed.

Now, let's update `src/main.rs` too so that it can use the WebSocket logic we just wrote:

```rust
use actix_files::NamedFile;
// Add HttpRequest and HttpResponse
use actix_web::{middleware, web, App, Error, HttpRequest, HttpResponse, HttpServer, Responder};
use actix_web_actors::ws;

// Import the WebSocket logic we wrote earlier.
mod server;
use self::server::MyWebSocket;

async fn index() -> impl Responder {
    NamedFile::open_async("./static/index.html").await.unwrap()
}

// WebSocket handshake and start `MyWebSocket` actor.
async fn websocket(req: HttpRequest, stream: web::Payload) -> Result<HttpResponse, Error> {
    ws::start(MyWebSocket::new(), &req, stream)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));

    log::info!("starting HTTP server at http://localhost:8080");

    HttpServer::new(|| {
        App::new()
            .service(web::resource("/").to(index))
            // Add the WebSocket route
            .service(web::resource("/ws").route(web::get().to(websocket)))
            .wrap(middleware::Logger::default())
    })
    .workers(2)
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
```

Now that our server logic is finished, we can finally start the server with the following command:

```bash
cargo run -- main src/main
```

Going to the browser and typing in `http://localhost:8080` should show a blank index page.

## Sending The Test File

Currently, if a client were to send text to the server, through the WebSocket, we'd echo it back to them.
But, we aren't concerned with the text that is sent over the socket. Whatever the client sends, we'll respond with the test file, since that's the sole purpose of our server. So, let's update the `Text` case in the `handle()` function to do that:

```rust
// ...
Ok(ws::Message::Text(_)) => {
    let file = File::open("./static/10mb").unwrap();
    let mut reader = BufReader::new(file);
    let mut buffer = Vec::new();

    reader.read_to_end(&mut buffer).unwrap();
    ctx.binary(Bytes::from(buffer));
}
// ...
```

Now, whenever a client sends text to the server through the WebSocket, we'll write the 10mb file to a buffer and send that to the client as binary data.

## Creating The Speed Test Client

Now, we can create a client that can send text to the server and receive the test file as a response. Open up `static/index.html` and add the following:

```html
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta http-equiv="X-UA-Compatible" content="ie=edge" />
        <title>Speed Test | Koyeb</title>

        <style>
            :root {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI",
                    Roboto, Oxygen, Ubuntu, Cantarell, "Open Sans",
                    "Helvetica Neue", sans-serif;
                font-size: 14px;
            }

            .container {
                max-width: 500px;
                width: 100%;
                height: 70vh;
                margin: 15vh auto;
            }

            #log {
                width: calc(100% - 24px);
                height: 20em;
                overflow: auto;
                margin: 0.5em 0;
                padding: 12px;

                border: 1px solid black;
                border-radius: 12px;

                font-family: monospace;
                background-color: black;
            }

            #title {
                float: left;
                margin: 12px 0;
            }

            #start {
                float: right;
                margin: 12px 0;

                background-color: black;
                color: white;
                font-size: 18px;
                padding: 4px 8px;
                border-radius: 4px;
                border: none;
            }

            #start:disabled,
            #start[disabled] {
                background-color: rgb(63, 63, 63);
                color: lightgray;
            }

            .msg {
                margin: 0;
                padding: 0.25em 0.5em;
                color: white;
            }

            .msg--bad {
                color: lightcoral;
            }

            .msg--success,
            .msg--good {
                color: lightgreen;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div>
                <h1 id="title">Speed Test</h1>
                <button id="start">start</button>
            </div>
            <div id="log"></div>
            <div>
                <p>
                    Powered by
                    <a href="https://www.koyeb.com/" target="_blank"> Koyeb</a>.
                </p>
            </div>
        </div>
        <script></script>
    </body>
</html>
```

When we visit `http://localhost:8080` in the browser, we should now see the following:

![Speed Test Homepage](https://i.imgur.com/4HmzeKD.png)

Great! Now we need to add some JavaScript, so this page can perform the test. Add the following script inside the `<script>` tag:

```javascript
const $startButton = document.querySelector("#start");
const $log = document.querySelector("#log");
// Calculate average from array of numbers
const average = (array) => array.reduce((a, b) => a + b) / array.length;
const totalTests = 10;
let startTime,
    endTime,
    testResults = [];

/** @type {WebSocket | null} */
var socket = null;

function log(msg, type = "status") {
    $log.innerHTML += `<p class="msg msg--${type}">${msg}</p>`;
    $log.scrollTop += 1000;
}

function start() {
    complete();

    const { location } = window;

    const proto = location.protocol.startsWith("https") ? "wss" : "ws";
    const wsUri = `${proto}://${location.host}/ws`;
    let testsRun = 0;

    log("Starting...");
    socket = new WebSocket(wsUri);

    // When the socket is open, we'll update the button
    // the test status and send the first test request.
    socket.onopen = () => {
        log("Started.");
        // This function updates the "Start" button
        updateTestStatus();
        testsRun++;
        // Get's the time before the first test request
        startTime = performance.now();
        socket.send("start");
    };

    socket.onmessage = (ev) => {
        // Get's the time once the message is received
        endTime = performance.now();

        // Creates a log that indicates the test case is finished
        // and the time it took to complete the test.
        log(
            `Completed Test: ${testsRun}/${totalTests}. Took ${
                endTime - startTime
            } milliseconds.`
        );
        // We'll store the test results for calculating the average later
        testResults.push(endTime - startTime);

        if (testsRun < totalTests) {
            testsRun++;
            startTime = performance.now();
            socket.send("start");
        } else complete();
    };

    // When the socket is closed, we'll log it and update the "Start" button
    socket.onclose = () => {
        log("Finished.", "success");
        socket = null;
        updateTestStatus();
    };
}

function complete() {
    if (socket) {
        log("Cleaning up...");
        socket.close();
        socket = null;

        // Calculates the average time it took to complete the test
        let testAverage = average(testResults) / 1000;
        // 10mb were sent. So MB/s is # of mega bytes divided by the
        // average time it took to complete the tests.
        let mbps = 10 / testAverage;

        // Change log color based on result
        let status;
        if (mbps < 10) status = "bad";
        else if (mbps < 50) status = "";
        else status = "good";

        // Log the results
        log(
            `Average speed: ${mbps.toFixed(2)} MB/s or ${(mbps * 8).toFixed(
                2
            )} Mbps`,
            status
        );

        // Update the "Start" button
        updateTestStatus();
    }
}

function updateTestStatus() {
    if (socket) {
        $startButton.disabled = true;
        $startButton.innerHTML = "Running";
    } else {
        $startButton.disabled = false;
        $startButton.textContent = "Start";
    }
}

// When the "Start" button is clicked, we'll start the test
// and update the "Start" button to indicate the test is running.
$startButton.addEventListener("click", () => {
    if (socket) complete();
    else start();

    updateTestStatus();
});

updateTestStatus();
log('Click "Start" to begin.');
```

Nice, now our client is complete. It looks a bit overwhelming, but it's not. All it's doing is sending 10 requests to the server, and then calculating the average time it took to complete each request.

## Deploying to Koyeb

For deployment, we'll be using Docker. Docker is a lightweight containerization tool that allows us to run our server in a container.

To Dockerize our server, let's create a simple `Dockerfile` in the root of our the project directory. Add the following to it:

```dockerfile
FROM rust:1.59.0

WORKDIR /usr/src/koyeb-fast-com
COPY . .

RUN cargo install --path .

EXPOSE 8080

CMD ["koyeb-fast-com-server"]
```

For consistency, name the working directory after the package name in the `Cargo.toml` file. In our case, it's `koyeb-fast-com`.

Let's break down what this file is doing. When we build the Docker image, it will download an official existing image for Rust, create the working directory and copy all of our project files into said directory. Then it will run the `cargo install` command to install all of our dependencies and expose port 8080.

A small thing that might help build times is to create a `.dockerignore` file in the root of the project directory. Add the following to it:

```dockerignore
target
```

This way, when we build the Docker image, it will ignore the `target` directory, which is where the `cargo build` command creates the final executable.

The last and most important part is that it will run the `koyeb-fast-com-server` command to start the server. We'll need to define this command in the `Cargo.toml` file:

```toml
[package]
name = "koyeb-fast-com"
version = "1.0.0"
edition = "2021"

[[bin]]
name = "koyeb-fast-com-server"
path = "src/main.rs"

[dependencies]
(* ... *)
```

The last thing we must do to ensure our project works in the Docker container is to change the bind address in `src/main.rs` to `0.0.0.0` instead of `127.0.0.1`:

```rust
// ...
HttpServer::new(|| {
    App::new()
        .service(web::resource("/").to(index))
        .service(web::resource("/ws").route(web::get().to(echo_ws)))
        .wrap(middleware::Logger::default())
})
.workers(2)
.bind(("0.0.0.0", 8080))? // Change bind address to 0.0.0.0
.run()
.await
// ...
```

Now let's build an image for our project:

```bash
docker build . -t ghcr.io/<YOUR_GITHUB_USERNAME>/koyeb-fast-com
```

We can see if it runs by running the following command:

```bash
docker run -p 8080:8080 ghcr.io/<YOUR_GITHUB_USERNAME>/my-project
```

Now that we know our project runs in the container, let's push it to the registry:

```bash
docker push ghcr.io/<YOUR_GITHUB_USERNAME>/my-project
```

It's now time to deploy our container image on Koyeb. On the Koyeb Control Panel, click the "Create App" button.

In the form, fill the Docker image field with the name of the image we previously created, which should look like `ghcr.io/<YOUR_GITHUB_USERNAME>/my-project`.

Check the box "Use a private registry" and, in the select field, click "Create Registry Secret."

A modal opens asking for:

-   A name for this new Secret (e.g. gh-registry-secret)
-   The registry provider to generate the secret containing your private registry credentials. In our case, GitHub.
-   Your GitHub username and a valid GitHub token having registry read/write permissions (for packages) as  
    password. You can create one here: [github.com/settings/tokens](https://github.com/settings/tokens)
-   Once you've filled all the fields, click the Create button.

Name your app and then click the "Create App" button. You will automatically be redirected to the Koyeb App page, where you can follow the progress of your application's deployment.

In a matter of seconds, once your app is deployed, click on the Public URL ending with `koyeb.app`. You should see your speed test site in action!

For a demo, click here: [speedtest-ceiphr.koyeb.app](https://speedtest-ceiphr.koyeb.app/).

## Conclusion

You now have your very own speed test site written in Rust, Dockerized, and hosted on Koyeb. With Koyeb's container-based deployment, anytime you push a new image to GitHub, just redeploy on Koyeb, and you're done. So, if you ever decide to add additional features or make the tests more robust, you can simply push your changes to GitHub and deploy!

If you'd like to learn more about Rust and Actix, check out [actix/examples](https://github.com/actix/examples/tree/master/websockets) and [actix-web](https://github.com/actix/actix-web). This article was actually based off the echo example from Actix, found [here](https://github.com/actix/examples/tree/master/websockets/echo).

If you have any questions or suggestions to improve this guide, feel free to reach out to us on [Slack](https://slack.koyeb.com/).
