# https://spark.apache.org/docs/latest/running-on-kubernetes.html
FROM vanillaspark:v2.4.5
## install pandas in alpine https://github.com/docker-library/python/issues/381
## https://github.com/pandas-dev/pandas/issues/25207
## slow image build https://stackoverflow.com/questions/49037742/why-does-it-take-ages-to-install-pandas-on-alpine-linux

ARG BUILD_DATE
ARG BUILD_VERSION

# Labels.
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.build-date=$BUILD_DATE
LABEL org.label-schema.gcr-name=""
LABEL org.label-schema.description="Spark on Kubernetes with GCS"
LABEL org.label-schema.vendor="KPMG"
LABEL org.label-schema.version=$BUILD_VERSION
LABEL org.label-schema.docker.cmd="docker run --rm "

RUN apk add --no-cache \
            git \
            build-base \
            cmake \
            bash \
            boost-dev \
            autoconf \
            zlib-dev \
            flex \
            bison

RUN apk --update add --no-cache python3-dev libstdc++ && \
    apk --update add --no-cache g++ && \
    ln -s /usr/include/locale.h /usr/include/xlocale.h && \
    pip3.6 install numpy==1.16.1 && \
    pip3.6 install pandas==0.24.1 && \
    pip3.6 install six cython pytest


## OBSOLETE: RUN git clone https://github.com/apache/arrow.git /arrow
## The Git clone is for pyarrow V15, which is unstable. The following is the fix.
## The blog reference for the fix: https://gist.github.com/bskaggs/fc3c8d0d553be54e2645616236fdc8c6 
## V12 was used in the blog post. But we tested V13 in the local conda install, and it worked. 

# alpine does not work with pip install pyarrow, old version of arrow has issue
ARG ARROW_VERSION=0.16.0
RUN mkdir /arrow \
    && apk add --no-cache curl \
    && curl -o /tmp/apache-arrow.tar.gz -SL https://github.com/apache/arrow/archive/apache-arrow-${ARROW_VERSION}.tar.gz \
    && tar -xvf /tmp/apache-arrow.tar.gz -C /arrow --strip-components 1

RUN mkdir -p /arrow/cpp/build
WORKDIR /arrow/cpp/build
ENV ARROW_BUILD_TYPE=release
ENV ARROW_HOME=/usr/local
ENV PARQUET_HOME=/usr/local

#disable backtrace
RUN sed -i -e '/_EXECINFO_H/,/endif/d' -e '/execinfo/d' ../src/arrow/util/logging.cc

RUN cmake -DCMAKE_BUILD_TYPE=$ARROW_BUILD_TYPE \
          -DPYTHON_EXECUTABLE=/usr/bin/python3.6 \
          -DCMAKE_INSTALL_LIBDIR=lib \
          -DCMAKE_INSTALL_PREFIX=$ARROW_HOME \
          -DARROW_PARQUET=on \
          -DARROW_PYTHON=on \
          -DARROW_PLASMA=on \
          -DARROW_BUILD_TESTS=OFF \
          ..
RUN make -j$(nproc)
RUN make install

WORKDIR /arrow/python
RUN /usr/bin/python3.6 setup.py build_ext --build-type=$ARROW_BUILD_TYPE \
       --with-parquet --inplace \
    && /usr/bin/python3.6 setup.py install



#/opt/spark/work-dir workdir of original spark image
RUN mkdir -p /app
WORKDIR /app

     
RUN rm $SPARK_HOME/jars/guava-14.0.1.jar
#dial tcp: lookup central.maven.org on 169.254.169.254:53: no such host
ADD https://repo1.maven.org/maven2/com/google/guava/guava/23.0/guava-23.0.jar $SPARK_HOME/jars

#The issue is described in following post (the kubernetes-client has bug with later version of Kubernetes)
#https://stackoverflow.com/questions/57643079/kubernetes-watchconnectionmanager-exec-failure-http-403
RUN rm $SPARK_HOME/jars/kubernetes-client-4.1.2.jar
ADD https://repo1.maven.org/maven2/io/fabric8/kubernetes-client/4.4.2/kubernetes-client-4.4.2.jar $SPARK_HOME/jars

# Add the connector jar needed to access Google Cloud Storage using the Hadoop FileSystem API.
ADD https://storage.googleapis.com/hadoop-lib/gcs/gcs-connector-latest-hadoop2.jar $SPARK_HOME/jars

# Add dependency for hadoop-aws
ADD http://central.maven.org/maven2/com/amazonaws/aws-java-sdk/1.7.4/aws-java-sdk-1.7.4.jar $SPARK_HOME/jars
# Add hadoop-aws to access Amazon S3
ADD http://central.maven.org/maven2/org/apache/hadoop/hadoop-aws/2.7.5/hadoop-aws-2.7.5.jar $SPARK_HOME/jars

# Add dependency for hadoop-azure
ADD http://central.maven.org/maven2/com/microsoft/azure/azure-storage/3.1.0/azure-storage-3.1.0.jar $SPARK_HOME/jars
# Add hadoop-azure to access Azure Blob Storage
ADD http://central.maven.org/maven2/org/apache/hadoop/hadoop-azure/2.7.4/hadoop-azure-2.7.4.jar $SPARK_HOME/jars

# https://github.com/AGLEnergy/arc/blob/master/Dockerfile

ENTRYPOINT [ "/opt/entrypoint.sh" ]
