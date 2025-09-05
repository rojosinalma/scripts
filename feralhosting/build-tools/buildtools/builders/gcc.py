"""
GCC builder for build-tools.

This module handles building GNU GCC compiler collection.
GCC must be built after binutils and configured to use the new binutils.
"""

from pathlib import Path
from typing import List

from .base_builder import BaseBuilder
from ..utils import print_info, print_warning


class GccBuilder(BaseBuilder):
    """Builder for GNU GCC."""
    
    def get_dependencies(self) -> List[str]:
        """GCC depends on binutils."""
        return ['binutils']
    
    def get_configure_args(self) -> List[str]:
        """Get configure arguments for GCC."""
        # Point to our newly built binutils
        binutils_dir = Path(self.local_prefix) / 'binutils'
        
        return [
            f'--prefix={self.install_dir}',
            f'--with-ld={binutils_dir}/bin/ld',
            f'--with-as={binutils_dir}/bin/as',
            '--disable-nls',
            '--enable-languages=c,c++',
            '--disable-multilib',
            '--enable-default-pie',
            '--enable-default-ssp'
        ]
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """GCC should be built in a separate directory."""
        build_dir = self.downloads_dir / f"{self.tool_name}-{self.version}-build"
        build_dir.mkdir(exist_ok=True)
        return build_dir
    
    def pre_build_setup(self, src_dir: Path) -> bool:
        """Download GCC prerequisites before building."""
        print_info("Downloading GCC prerequisites...")
        
        # Try to download prerequisites automatically
        prereq_script = src_dir / 'contrib' / 'download_prerequisites'
        if prereq_script.exists():
            prereq_cmd = ['./contrib/download_prerequisites']
            if not self.run_build_command(prereq_cmd, src_dir, {}):
                print_warning("Failed to download prerequisites automatically")
                print_info("You may need to download them manually")
                # Don't fail the build - prerequisites might already be present
        else:
            print_warning("Prerequisites download script not found")
        
        return True