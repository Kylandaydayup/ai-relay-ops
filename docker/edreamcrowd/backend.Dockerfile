ARG MAVEN_BASE_IMAGE=maven:3.9.9-eclipse-temurin-21
ARG RUNTIME_BASE_IMAGE=eclipse-temurin:21-jre

FROM ${MAVEN_BASE_IMAGE} AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

FROM ${RUNTIME_BASE_IMAGE}

WORKDIR /app
COPY --from=build /app/target/backend-0.0.1-SNAPSHOT.jar /app/app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
