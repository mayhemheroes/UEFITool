FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gcc g++ make cmake git

ADD . /UEFITool
WORKDIR /UEFITool/UEFIExtract
RUN git clean -d -f -x 
RUN cmake .
RUN make

FROM ubuntu:20.04 as package

COPY --from=builder /UEFITool /