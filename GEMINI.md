# Legado Project Overview

This document provides a comprehensive overview of the Legado project, including its purpose, structure, and instructions for building and running the different components.

## 1. Project Purpose

Legado is a free and open-source novel reader for Android. It allows users to read novels from various sources by defining custom source rules. The project also includes a web interface for managing book sources and reading on a browser.

## 2. Project Structure

This is a multi-module project primarily built with Gradle. It consists of an Android application and a web application.

*   **`/app`**: The main Android application module. It contains the core application logic, UI, and services.
*   **`/modules`**: Contains sub-modules used by the main application.
    *   **`/modules/book`**: A module related to book processing.
    *   **`/modules/rhino`**: A module that integrates the Rhino JavaScript engine.
    *   **`/modules/web`**: A Vue.js-based web application that interacts with the Android app's API.
*   **`/gradle`**: Contains Gradle wrapper and dependency versioning configurations.
*   **`/api.md`**: Detailed documentation of the Web and Content Provider APIs exposed by the Android application.

## 3. Technologies Used

*   **Android App**:
    *   **Languages**: Kotlin, Java
    *   **Build Tool**: Gradle
    *   **Key Libraries**:
        *   AndroidX (AppCompat, Core KTX, Room, etc.)
        *   Coroutines for asynchronous programming
        *   Retrofit and OkHttp for networking
        *   Glide for image loading
        *   NanoHTTPD for the embedded web server

*   **Web App**:
    *   **Framework**: Vue.js
    *   **Build Tool**: Vite
    *   **Language**: TypeScript
    *   **Package Manager**: pnpm

## 4. Building and Running the Project

### Android Application

1.  **Prerequisites**:
    *   Android Studio
    *   Android SDK

2.  **Building**:
    *   Open the project in Android Studio.
    *   Let Gradle sync and download the dependencies.
    *   To build an APK, you can use the Gradle wrapper command from the root directory:
        ```bash
        ./gradlew :app:assembleDebug
        ```
    *   The generated APK will be located in `/app/build/outputs/apk/debug/`.

3.  **Running**:
    *   You can run the application directly on a connected Android device or emulator from Android Studio.

### Web Application

1.  **Prerequisites**:
    *   Node.js (version >= 20)
    *   pnpm package manager (version >= 9)

2.  **Setup**:
    *   Navigate to the web module directory:
        ```bash
        cd modules/web
        ```
    *   Install the dependencies:
        ```bash
        pnpm install
        ```

3.  **Running in Development Mode**:
    *   To start the development server, run:
        ```bash
        pnpm run dev
        ```
    *   This will start a local server, typically at `http://localhost:5173`.

4.  **Building for Production**:
    *   To build the static assets for production, run:
        ```bash
        pnpm run build
        ```
    *   The output will be in the `modules/web/dist` directory.

## 5. Development Conventions

*   **Android**: The project follows standard Android development conventions. It uses libraries like Room for database and Coroutines for background tasks.
*   **Web**: The web module uses ESLint and Prettier for code formatting and linting. It is recommended to use an editor with corresponding plugins to maintain code quality.
*   **API**: The application exposes a Web API and a Content Provider API for interacting with the application data. See `api.md` for more details.
