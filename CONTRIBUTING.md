# Contributing to Ditana

Thank you for your interest in contributing to Ditana! This document provides guidelines for contributing to the Ditana project, helping to maintain consistency and quality across our codebase.

## Project Structure

Ditana consists of the following components:

- **Installer Repository**: [https://github.com/acrion/ditana-installer](https://github.com/acrion/ditana-installer)
  - Contains the installer and ISO generator
  - Based on `/usr/share/archiso/configs/releng` from the Arch `archiso` package
  - Main code is in the `airootfs/root/` directory, primarily written in Raku

- **Ditana Packages**: All official Ditana packages are listed in the README of the installer repository and documented on [ditana.org](https://ditana.org/docs/the-packages/).

## Development Environment Setup

### Prerequisites

- An Arch Linux-based system (preferably Ditana itself)
- Git
- Raku (install via `rakudo-bin` package)

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/acrion/ditana-installer.git
   cd ditana-installer
   ```

### Building the ISO

To build the Ditana ISO:

```bash
./build.sh
```

**Note**: If your current Git branch differs from `main`, the build process will automatically use the Ditana Testing Arch Repository. This allows testing changes to Ditana Arch packages before they are transferred to the official repository.

### Testing the Installer

You can test the installer in a simulation environment without affecting your system:

```bash
cd airootfs/root
./run-ditana-installer.sh
```

This opens a tmux session to display the installation status alongside the dialogs. If you find this distracting, you can run the installer without tmux:

```bash
cd airootfs/root
./main.sh
```

The installer detects a simulation environment when `$USER ne 'root'` (see `real-install` setting in `airootfs/root/settings.json`). In simulation mode, the installer will not modify your system, although it may still request root password at certain points to retrieve hardware information. The log file in simulation mode is stored at `/tmp/install_ditana.log`.

## How to Contribute

### Reporting Bugs

If you encounter any issues:

1. Check if the issue already exists in the [GitHub Issues](https://github.com/acrion/ditana-installer/issues)
2. If not, create a new issue with a descriptive title and detailed information:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Screenshots if applicable
   - System information (hardware, OS version)
   - Installation logs if available

### Suggesting Enhancements

We welcome suggestions for improvements:

1. Open an issue on GitHub
2. Use a clear title and provide a detailed description
3. Explain why this enhancement would be useful
4. Suggest an implementation approach if possible

### Code Contributions

For code contributions:

1. Create a new branch for your feature or fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
   or
   ```bash
   git checkout -b fix/issue-you-are-fixing
   ```

2. Test your changes thoroughly
3. Commit your changes with clear, descriptive commit messages
4. Push to your fork and submit a pull request

### Pull Request Process

1. Ensure your PR has a clear description of the changes and their purpose
2. Link any relevant issues
3. Make sure your code passes all tests
4. Be responsive to feedback and be prepared to make requested changes

## Testing

Before submitting a pull request:

1. Ensure the ISO builds correctly
2. Test the installer in simulation mode
3. If possible, test in a virtual machine with various hardware configurations
4. Verify that the installation completes successfully and the resulting system works as expected

## Documentation

Improvements to documentation are highly appreciated:

- Update the README.md with new features or changes
- Document new configuration options
- Add or update user guides and tutorials
- Correct any outdated information

## License

By contributing to Ditana, you agree that your contributions will be licensed under the project's license.

Thank you for helping improve Ditana!
