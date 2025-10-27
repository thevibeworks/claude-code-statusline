# Contributing to Claude Code Statusline

Thank you for your interest in contributing to Claude Code Statusline! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- Node.js 18+ and npm
- Git
- A Claude API key for testing

### Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/your-username/claude-code-statusline.git
   cd claude-code-statusline
   ```

3. Install dependencies:
   ```bash
   npm install
   ```

4. Create a `.env` file:
   ```bash
   cp .env.example .env
   # Add your Claude API key to .env
   ```

5. Build the project:
   ```bash
   npm run build
   ```

6. Run tests:
   ```bash
   npm test
   ```

## Development Workflow

### Building

```bash
# One-time build
npm run build

# Watch mode for development
npm run dev
```

### Testing

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test -- --watch

# Run tests with coverage
npm run test -- --coverage
```

### Linting

```bash
# Run ESLint
npm run lint

# Fix auto-fixable issues
npm run lint -- --fix
```

### Demo

```bash
# Run the demo showcase
node demo/showcase.js
```

## Code Style

- Use TypeScript for all source code
- Follow the existing code style
- Use meaningful variable and function names
- Add JSDoc comments for public APIs
- Keep functions small and focused

## Project Structure

```
├── src/
│   ├── __tests__/       # Test files
│   ├── services/        # API and telemetry services
│   ├── types/           # TypeScript type definitions
│   ├── ui/              # UI rendering components
│   ├── utils/           # Utility functions
│   ├── cli.ts           # CLI entry point
│   ├── monitor.ts       # Main monitor class
│   └── index.ts         # Library exports
├── demo/                # Demo scripts
├── dist/                # Build output (gitignored)
└── node_modules/        # Dependencies (gitignored)
```

## Adding New Features

### Adding a New Progress Bar Style

1. Add the style configuration to `src/ui/progressBar.ts`:
   ```typescript
   export const progressBarStyles: Record<ProgressBarStyle, any> = {
     // ... existing styles
     newstyle: {
       format: '{bar} {percentage}% | {value}/{total}',
       barCompleteChar: '▓',
       barIncompleteChar: '░',
       hideCursor: true,
     },
   };
   ```

2. Update the `ProgressBarStyle` type in `src/types/index.ts`
3. Add tests in `src/__tests__/progressBar.test.ts`
4. Update the README with the new style

### Adding a New Theme

1. Add the theme to `src/ui/themes.ts`:
   ```typescript
   export const themes: Record<ThemePreset, ThemeConfig> = {
     // ... existing themes
     newtheme: {
       name: 'New Theme',
       colors: {
         success: '#00ff00',
         warning: '#ffff00',
         danger: '#ff0000',
         info: '#00ffff',
         primary: '#ff00ff',
         secondary: '#ffa500',
       },
     },
   };
   ```

2. Update the `ThemePreset` type in `src/types/index.ts`
3. Add tests in `src/__tests__/themes.test.ts`
4. Update the README

### Adding a New Layout

1. Add a new render method in `src/ui/renderer.ts`:
   ```typescript
   private renderNewLayout(
     quotaLimits: QuotaLimits,
     subscription: SubscriptionMetadata,
     warnings: QuotaWarning[]
   ): string {
     // Implementation
   }
   ```

2. Update the `render()` method to include the new layout
3. Update the `LayoutType` type in `src/types/index.ts`
4. Add tests
5. Update the README

## Testing Guidelines

- Write tests for all new features
- Maintain or improve test coverage
- Test edge cases and error conditions
- Use descriptive test names
- Mock external dependencies (API calls, file system, etc.)

Example test:
```typescript
describe('MyFeature', () => {
  it('should handle empty input', () => {
    // Test implementation
  });

  it('should throw error for invalid input', () => {
    // Test implementation
  });
});
```

## Submitting Changes

1. Create a new branch for your feature:
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. Make your changes and commit:
   ```bash
   git add .
   git commit -m "Add: description of your changes"
   ```

3. Push to your fork:
   ```bash
   git push origin feature/my-new-feature
   ```

4. Create a Pull Request on GitHub

### Commit Message Guidelines

Use conventional commit format:

- `Add:` for new features
- `Fix:` for bug fixes
- `Update:` for updates to existing features
- `Remove:` for removing features
- `Docs:` for documentation changes
- `Test:` for test changes
- `Refactor:` for code refactoring

Examples:
- `Add: gradient progress bar style`
- `Fix: incorrect percentage calculation in warnings`
- `Update: improve error messages in API service`
- `Docs: add examples for custom themes`

## Pull Request Checklist

Before submitting a PR, ensure:

- [ ] Code builds without errors (`npm run build`)
- [ ] All tests pass (`npm test`)
- [ ] No linting errors (`npm run lint`)
- [ ] New features have tests
- [ ] Documentation is updated (README, JSDoc comments)
- [ ] Demo is updated if UI changes were made
- [ ] Commit messages follow the guidelines

## Reporting Issues

When reporting issues, please include:

- Clear description of the problem
- Steps to reproduce
- Expected behavior
- Actual behavior
- Environment details (Node.js version, OS, etc.)
- Error messages and stack traces if applicable

## Feature Requests

We welcome feature requests! When submitting:

- Describe the feature clearly
- Explain the use case
- Provide examples if possible
- Consider implementation complexity

## Questions?

Feel free to open an issue for questions or discussions about contributing.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
