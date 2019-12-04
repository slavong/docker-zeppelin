FROM openjdk:8-jre

RUN \
  sed -i 's/# \(.*multiverse$\)/\1/g' /etc/apt/sources.list && \
  apt-get update && \
  apt-get install -y \
    curl \
    grep \
    sed \
    git \
    wget \
    bzip2 \
    gettext \
    sudo \
    ca-certificates \
    libglib2.0-0 \
    libxext6 \
    libsm6 \
    libxrender1 \
    libaio1 \
    build-essential \
    unzip && \
  apt-get clean all

RUN echo 'export PATH=/opt/conda/bin:$PATH' > /etc/profile.d/conda.sh && \
  wget --quiet https://repo.continuum.io/archive/Anaconda2-4.2.0-Linux-x86_64.sh -O ~/anaconda.sh && \
  /bin/bash ~/anaconda.sh -b -p /opt/conda && \
  rm ~/anaconda.sh

RUN /opt/conda/bin/conda install SQLAlchemy psycopg2 pymssql cx_Oracle
RUN ln -s /opt/conda/bin/python /usr/bin/python

ADD spark /usr/local/spark

ADD zeppelin /usr/local/zeppelin
WORKDIR /usr/local/zeppelin

ADD shiro-tools-hasher-1.3.2-cli.jar .

RUN rm -rf conf

COPY conf.templates conf.templates

VOLUME ["/usr/local/zeppelin/notebooks"]
VOLUME ["/usr/local/zeppelin/conf"]
VOLUME ["/hive"]
VOLUME ["/etc/ssl/certs"]

EXPOSE 8080

COPY start-zeppelin.sh bin

ENTRYPOINT ["bin/start-zeppelin.sh"]
