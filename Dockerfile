FROM rust:1.72.0

WORKDIR /usr/src/koyeb-fast-com
COPY . .

RUN cargo install --path .

EXPOSE 8080

CMD ["koyeb-fast-com-server"]
