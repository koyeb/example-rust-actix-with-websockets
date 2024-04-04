<div align="center">
  <a href="https://koyeb.com">
    <img src="https://www.koyeb.com/static/images/icons/koyeb.svg" alt="Logo" width="80" height="80">
  </a>
  <h3 align="center">Koyeb Serverless Platform</h3>
  <p align="center">
    Deploy a Rust speed test using Actix and WebSockets on Koyeb
    <br />
    <a href="https://koyeb.com">Learn more about Koyeb</a>
    ·
    <a href="https://koyeb.com/docs">Explore the documentation</a>
    ·
    <a href="https://koyeb.com/tutorials">Discover our tutorials</a>
  </p>
</div>


## About Koyeb and the Rust speed test with Actix and WebSockets example application

Koyeb is a developer-friendly serverless platform to deploy apps globally. No-ops, servers, or infrastructure management.
This repository contains a Rust speed test you can deploy on the Koyeb serverless platform for testing.

This example application is designed to show how a Rust speed test using Actix and WebSockets can be deployed on Koyeb.

## Getting Started

Follow the steps below to deploy and run the Rust speed test using Actix and WebSockets on your Koyeb account.

### Requirements

You need a Koyeb account to successfully deploy and run this application. If you don't already have an account, you can sign-up for free [here](https://app.koyeb.com/auth/signup).

### Fork and deploy to Koyeb

If you want to customize and enhance this application, you need to fork this repository.

On the [Koyeb Control Panel](//app.koyeb.com/apps), on the **Overview** tab, click the **Create Web Service** button to begin.

1. Choose **Docker** as the deployment method.
2. Fill in the **Docker image** field with the name of the image we previously created, which should look like `ghcr.io/<YOUR_GITHUB_USERNAME>/koyeb-speed-test`.
3. Click the **Private image** toggle and select **Create secret**.  In the form that appears, fill out the following:
    -   A name for this new Secret (e.g. `gh-registry-secret`).
    -   The type of registry provider to simplify generating the Koyeb Secret containing your private registry credentials. In our case, **GitHub**.
    -   Your GitHub username and a valid GitHub token having registry read/write permissions (for packages) as the password. You can create one here: [github.com/settings/tokens](https://github.com/settings/tokens).
    -   Once you've filled all the fields, click the **Create** button.
4. Choose a name for your App and Service, for example `rust-actix`, and click **Deploy**.

You land on the deployment page where you can follow the build of your application. Once the build is completed, your application is being deployed and you will be able to access it via `<YOUR_APP_NAME>-<YOUR_ORG_NAME>.koyeb.app`.

## Contributing

If you have any questions, ideas or suggestions regarding this application sample, feel free to open an [issue](//github.com/koyeb/example-apollo-grapqhl-server-with-mongodb-atlas/issues) or fork this repository and open a [pull request](//github.com/koyeb/example-apollo-grapqhl-server-with-mongodb-atlas/pulls).

## Contact

[Koyeb](https://www.koyeb.com) - [@gokoyeb](https://twitter.com/gokoyeb) - [Slack](http://slack.koyeb.com/)
