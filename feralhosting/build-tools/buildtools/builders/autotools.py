"""
Autotools builders for build-tools.

This module handles building the GNU autotools suite:
- autoconf
- automake  
- libtool

These are built after GCC and Make, in dependency order.
"""

from pathlib import Path
from typing import List

from .base_builder import BaseBuilder


class AutoconfBuilder(BaseBuilder):
    """Builder for GNU Autoconf."""
    
    def get_dependencies(self) -> List[str]:
        """Autoconf depends on binutils, GCC, and Make."""
        return ['binutils', 'gcc', 'make']
    
    def get_configure_args(self) -> List[str]:
        """Get configure arguments for Autoconf."""
        return [
            f'--prefix={self.install_dir}'
        ]
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """Autoconf builds in source directory."""
        return src_dir


class AutomakeBuilder(BaseBuilder):
    """Builder for GNU Automake."""
    
    def get_dependencies(self) -> List[str]:
        """Automake depends on binutils, GCC, Make, and Autoconf."""
        return ['binutils', 'gcc', 'make', 'autoconf']
    
    def get_configure_args(self) -> List[str]:
        """Get configure arguments for Automake."""
        return [
            f'--prefix={self.install_dir}'
        ]
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """Automake builds in source directory."""
        return src_dir


class LibtoolBuilder(BaseBuilder):
    """Builder for GNU Libtool."""
    
    def get_dependencies(self) -> List[str]:
        """Libtool depends on all previous tools."""
        return ['binutils', 'gcc', 'make', 'autoconf', 'automake']
    
    def get_configure_args(self) -> List[str]:
        """Get configure arguments for Libtool."""
        return [
            f'--prefix={self.install_dir}'
        ]
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """Libtool builds in source directory."""
        return src_dir