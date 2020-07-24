FROM centos:7

RUN mkdir /usr/local/plots && \
        mkdir /usr/local/alita

WORKDIR /usr/local/alita

ADD alita .
ADD     jre-8u221-linux-x64.tar.gz .
ADD     Alita-miner-v1.0.0.zip .
ADD     glibc-2.18.tar.gz .

ENV JAVA_HOME /usr/local/alita/jre1.8.0_221
ENV PATH $PATH:$JAVA_HOME/bin

RUN yum install -y unzip make gcc g++ net-tools.x86_64 wget && \
        unzip Alita-miner-v1.0.0.zip && \
        cd glibc-2.18/ && \
        mkdir build/ && \
        cd build/ && \
        ../configure --prefix=/usr && \
        make -j4 && \
        make install && \
        cd /usr/local/alita

ADD initation.sh .

ENTRYPOINT ["sh","initation.sh"]
