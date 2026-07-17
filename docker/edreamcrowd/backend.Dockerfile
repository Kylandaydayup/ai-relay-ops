ARG MAVEN_BASE_IMAGE=maven:3.9.9-eclipse-temurin-21
ARG RUNTIME_BASE_IMAGE=eclipse-temurin:21-jre

FROM ${MAVEN_BASE_IMAGE} AS build
WORKDIR /app
ARG MAVEN_MIRROR_URL=https://maven.aliyun.com/repository/public
RUN printf '%s\n' \
      '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">' \
      '  <mirrors>' \
      '    <mirror>' \
      '      <id>edream-mirror</id>' \
      '      <mirrorOf>*</mirrorOf>' \
      "      <url>${MAVEN_MIRROR_URL}</url>" \
      '    </mirror>' \
      '  </mirrors>' \
      '</settings>' \
      > /tmp/maven-settings.xml
COPY pom.xml .
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -s /tmp/maven-settings.xml -DskipTests package

FROM ${RUNTIME_BASE_IMAGE}

WORKDIR /app
COPY --from=build /app/target/backend-0.0.1-SNAPSHOT.jar /app/app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
