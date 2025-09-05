"""
Binutils builder for build-tools.

This module handles building GNU binutils (assembler, linker, etc.).
Binutils must be built first as it provides tools needed by GCC.
"""

from pathlib import Path
from typing import List

from .base_builder import BaseBuilder


class BinutilsBuilder(BaseBuilder):
    """Builder for GNU binutils."""
    
    def get_dependencies(self) -> List[str]:
        """Binutils has no dependencies - it's built first with system tools."""
        return []
    
    def get_configure_args(self) -> List[str]:
        """Get configure arguments for binutils."""
        return [
            f'--prefix={self.install_dir}',
            '--disable-nls',
            '--disable-werror',
            '--enable-gold',
            '--enable-ld=default',
            '--enable-plugins',
            '--with-system-zlib'
        ]
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """Binutils should be built in a separate directory."""
        build_dir = self.downloads_dir / f"{self.tool_name}-{self.version}-build"
        build_dir.mkdir(exist_ok=True)
        return build_dir