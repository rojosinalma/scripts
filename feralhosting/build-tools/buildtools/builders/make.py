"""
GNU Make builder for build-tools.

This module handles building GNU Make.
Make is built after GCC so it uses the new compiler.
"""

from pathlib import Path
from typing import List

from .base_builder import BaseBuilder


class MakeBuilder(BaseBuilder):
    """Builder for GNU Make."""
    
    def get_dependencies(self) -> List[str]:
        """Make depends on binutils and GCC."""
        return ['binutils', 'gcc']
    
    def get_configure_args(self) -> List[str]:
        """Get configure arguments for Make."""
        return [
            f'--prefix={self.install_dir}',
            '--disable-nls'
        ]
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """Make should be built in a separate directory."""
        build_dir = self.downloads_dir / f"{self.tool_name}-{self.version}-build"
        build_dir.mkdir(exist_ok=True)
        return build_dir