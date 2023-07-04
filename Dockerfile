FROM rust:1.70.0

WORKDIR /usr/src/koyeb-fast-com
COPY . .

RUN cargo install --path .

EXPOSE 8080

CMD ["koyeb-fast-com-server"]
