# Contributing to ClaudeMeter

Thank you for your interest in contributing to ClaudeMeter! This document provides guidelines and instructions for contributing.

## Development Setup

### Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/ClaudeMeter.git
   cd ClaudeMeter
   ```
3. Open `ClaudeMeter.xcodeproj` in Xcode
4. Build and run the project (⌘+R)

### Project Structure

```
ClaudeMeter/
├── App/                    # Application entry points
│   ├── ClaudeMeterApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
├── Core/
│   ├── Constants.swift     # Centralized configuration
│   ├── DependencyContainer.swift
│   ├── Protocols/          # Service protocols for DI
│   ├── Models/             # Data models
│   ├── Services/           # API, Keychain, Notifications
│   └── Managers/           # Business logic managers
├── UI/
│   ├── MenuBar/            # Status bar components
│   ├── Popover/            # Main popover views
│   ├── Settings/           # Settings views
│   └── Components/         # Reusable UI components
└── Extensions/             # Swift extensions
```

## Code Guidelines

### Swift Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Keep functions focused and small
- Prefer value types (structs/enums) over reference types where appropriate

### Architecture

- Use protocol-based abstractions for services
- Inject dependencies through constructors
- Keep UI logic in Views, business logic in Managers
- Use `Constants` for all magic numbers and strings

### Documentation

- Add documentation comments for public APIs
- Use `// MARK: -` to organize code sections
- Include license headers in all Swift files:
  ```swift
  //
  //  FileName.swift
  //  ClaudeMeter
  //
  //  Copyright (c) 2026 puq.ai. All rights reserved.
  //  Licensed under the MIT License. See LICENSE file.
  //
  ```

### Testing

- Write unit tests for new functionality
- Use mock implementations for protocol-based services
- Ensure all tests pass before submitting PR

## Pull Request Process

1. Create a feature branch from `main`:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the code guidelines

3. Run tests and ensure they pass:

   ```bash
   xcodebuild test -scheme ClaudeMeter
   ```

4. Build and verify the app works:

   ```bash
   xcodebuild build -scheme ClaudeMeter
   ```

5. Commit your changes with clear commit messages:

   ```bash
   git commit -m "Add feature: description of your changes"
   ```

6. Push to your fork and create a Pull Request

7. Ensure your PR description includes:
   - What changes were made
   - Why the changes were necessary
   - How to test the changes
   - Screenshots (for UI changes)

## Reporting Issues

When reporting issues, please include:

- macOS version
- ClaudeMeter version
- Steps to reproduce
- Expected behavior
- Actual behavior
- Relevant logs or screenshots

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow

## Questions?

If you have questions, feel free to:

- Open a GitHub issue
- Start a discussion in the Discussions tab

Thank you for contributing to ClaudeMeter!

---

**Maintained by [puq.ai](https://puq.ai)**
