"""
Build Tools - Modular GCC Toolchain Builder

This package provides a modular system for building GNU development tools
on Debian 9 systems without requiring root privileges.

Main modules:
- config: Configuration and version management
- utils: Utility functions and colored output
- downloader: Source download and extraction
- mirror_tester: Mirror speed testing
- builders: Tool-specific build logic

Usage:
    from buildtools.config import get_versions
    from buildtools.builders.gcc import GccBuilder
"""

__version__ = "1.0.0"
__author__ = "Build Tools"
__description__ = "Modular GCC toolchain builder for Debian 9"

# Make common functionality easily accessible
from .config import get_versions, BUILD_ORDER, COMPATIBILITY_SETS
from .utils import (
    print_info, print_success, print_warning, print_error,
    setup_signal_handlers
)

__all__ = [
    'get_versions',
    'BUILD_ORDER', 
    'COMPATIBILITY_SETS',
    'print_info',
    'print_success', 
    'print_warning',
    'print_error',
    'setup_signal_handlers'
]