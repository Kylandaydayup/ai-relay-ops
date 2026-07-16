ARG MAVEN_BASE_IMAGE=maven:3.9.9-eclipse-temurin-21

FROM ${MAVEN_BASE_IMAGE}

ARG MAVEN_MIRROR_URL=https://maven.aliyun.com/repository/public

WORKDIR /app

RUN mkdir -p /root/.m2 \
    && printf '%s\n' \
      '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">' \
      '  <mirrors>' \
      '    <mirror>' \
      '      <id>edream-default</id>' \
      '      <mirrorOf>*</mirrorOf>' \
      "      <url>${MAVEN_MIRROR_URL}</url>" \
      '    </mirror>' \
      '  </mirrors>' \
      '</settings>' \
      > /root/.m2/settings.xml

COPY pom.xml .
RUN mvn -B -DskipTests dependency:go-offline
