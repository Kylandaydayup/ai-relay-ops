ARG RUNTIME_IMAGE=eclipse-temurin:21-jre
FROM ${RUNTIME_IMAGE}

WORKDIR /app
COPY backend-0.0.1-SNAPSHOT.jar /app/app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
