"""
Base builder class for build-tools.

This module provides the common interface and functionality
that all tool builders inherit from.
"""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Dict, List, Optional

from ..utils import print_info, print_success, print_error, run_command, get_build_env
from ..downloader import extract_archive


class BaseBuilder(ABC):
    """Base class for all tool builders."""
    
    def __init__(self, tool_name: str, version: str, downloads_dir: Path, 
                 logs_dir: Path, local_prefix: str, make_jobs: int):
        self.tool_name = tool_name
        self.version = version
        self.downloads_dir = downloads_dir
        self.logs_dir = logs_dir
        self.local_prefix = local_prefix
        self.make_jobs = make_jobs
        
        # Derived paths
        self.archive_path = downloads_dir / f"{tool_name}-{version}.tar.gz"
        self.install_dir = Path(local_prefix) / tool_name
        self.log_file = logs_dir / f"{tool_name}.log"
    
    def extract_source(self) -> Optional[Path]:
        """Extract the source archive."""
        return extract_archive(self.archive_path, self.downloads_dir)
    
    def get_build_environment(self, tools_built: List[str]) -> Dict[str, str]:
        """Get the build environment with previously built tools in PATH."""
        return get_build_env(tools_built, self.local_prefix, self.make_jobs)
    
    def run_build_command(self, cmd: List[str], cwd: Path, env: Dict[str, str] = None, 
                         show_output: bool = False) -> bool:
        """Run a build command with proper logging."""
        return run_command(cmd, cwd, env, self.log_file, show_output)
    
    @abstractmethod
    def get_configure_args(self) -> List[str]:
        """Get configure arguments specific to this tool."""
        pass
    
    @abstractmethod
    def get_dependencies(self) -> List[str]:
        """Get list of tools that must be built before this one."""
        pass
    
    def pre_build_setup(self, src_dir: Path) -> bool:
        """Perform any pre-build setup. Override in subclasses if needed."""
        return True
    
    def post_build_setup(self) -> bool:
        """Perform any post-build setup. Override in subclasses if needed."""
        return True
    
    def build(self) -> bool:
        """Build the tool following the standard process."""
        print_info(f"Building {self.tool_name} {self.version}...")
        
        # Extract source
        src_dir = self.extract_source()
        if not src_dir:
            return False
        
        # Pre-build setup
        if not self.pre_build_setup(src_dir):
            print_error(f"Pre-build setup failed for {self.tool_name}")
            return False
        
        # Get build environment
        dependencies = self.get_dependencies()
        env = self.get_build_environment(dependencies)
        
        # Determine if we need a separate build directory
        build_dir = self.get_build_directory(src_dir)
        
        # Configure
        configure_args = self.get_configure_args()
        configure_cmd = [str(src_dir / 'configure')] + configure_args
        
        if not self.run_build_command(configure_cmd, build_dir, env):
            print_error(f"Failed to configure {self.tool_name}")
            return False
        
        # Make
        make_cmd = ['make', f'-j{self.make_jobs}']
        if not self.run_build_command(make_cmd, build_dir, env):
            print_error(f"Failed to build {self.tool_name}")
            return False
        
        # Install
        install_cmd = ['make', 'install']
        if not self.run_build_command(install_cmd, build_dir, env):
            print_error(f"Failed to install {self.tool_name}")
            return False
        
        # Post-build setup
        if not self.post_build_setup():
            print_error(f"Post-build setup failed for {self.tool_name}")
            return False
        
        print_success(f"Successfully built {self.tool_name} {self.version}")
        return True
    
    def get_build_directory(self, src_dir: Path) -> Path:
        """Get the build directory. Override if separate build dir is needed."""
        return src_dir
    
    def is_built(self) -> bool:
        """Check if the tool is already built and installed."""
        # Simple check - look for the bin directory
        bin_dir = self.install_dir / 'bin'
        return bin_dir.exists() and any(bin_dir.iterdir())
    
    def clean(self) -> bool:
        """Clean up build artifacts and installation."""
        import shutil
        
        try:
            # Remove installation directory
            if self.install_dir.exists():
                shutil.rmtree(self.install_dir)
                print_info(f"Removed {self.install_dir}")
            
            # Remove extracted source directory
            src_pattern = f"{self.tool_name}-{self.version}"
            for item in self.downloads_dir.iterdir():
                if item.is_dir() and item.name.startswith(src_pattern):
                    shutil.rmtree(item)
                    print_info(f"Removed {item}")
            
            # Remove build directory if separate
            build_pattern = f"{self.tool_name}-{self.version}-build"
            for item in self.downloads_dir.iterdir():
                if item.is_dir() and item.name == build_pattern:
                    shutil.rmtree(item)
                    print_info(f"Removed {item}")
            
            print_success(f"Cleaned {self.tool_name}")
            return True
        
        except Exception as e:
            print_error(f"Failed to clean {self.tool_name}: {e}")
            return False