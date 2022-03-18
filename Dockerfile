FROM rust:1.59.0

WORKDIR /usr/src/koyeb-fast-com
COPY . .

RUN cargo install --path .

CMD ["koyeb-fast-com-server"]