# Multi-stage build for the Spring Boot app
# Stage 1: build the jar
FROM eclipse-temurin:25-jdk AS build
WORKDIR /workspace

# Install dependencies using the Gradle wrapper
COPY gradlew settings.gradle build.gradle ./
COPY gradle gradle
RUN chmod +x gradlew
COPY src src

RUN ./gradlew bootJar -x test

# Stage 2: thin runtime image
FROM eclipse-temurin:25-jre
WORKDIR /app

# Copy the built jar (matches the project versioned artifact)
COPY --from=build /workspace/build/libs/*-SNAPSHOT.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java","-jar","/app/app.jar"]

