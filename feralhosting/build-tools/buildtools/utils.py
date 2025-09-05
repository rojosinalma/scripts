"""
Utility functions for build-tools.

This module provides colored output, logging, command execution,
and other common utilities used throughout the build system.
"""

import os
import subprocess
import signal
import sys
from pathlib import Path
from typing import Dict, List, Optional


# =============================================================================
# COLOR CODES AND OUTPUT
# =============================================================================

class Colors:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    RESET = '\033[0m'


def print_info(message: str):
    """Print info message with color."""
    print(f"{Colors.BLUE}[INFO]{Colors.RESET} {message}")


def print_success(message: str):
    """Print success message with color."""
    print(f"{Colors.GREEN}[SUCCESS]{Colors.RESET} {message}")


def print_warning(message: str):
    """Print warning message with color."""
    print(f"{Colors.YELLOW}[WARNING]{Colors.RESET} {message}")


def print_error(message: str):
    """Print error message with color."""
    print(f"{Colors.RED}[ERROR]{Colors.RESET} {message}")


# =============================================================================
# SIGNAL HANDLING
# =============================================================================

interrupted = False


def signal_handler(signum, frame):
    """Handle interruption signals gracefully."""
    global interrupted
    interrupted = True
    print_error("\nBuild interrupted by user")
    sys.exit(1)


def setup_signal_handlers():
    """Set up signal handlers for graceful interruption."""
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)


# =============================================================================
# COMMAND EXECUTION
# =============================================================================

def run_command(cmd: List[str], cwd: Path, env: Dict[str, str] = None, 
                log_file: Path = None, show_output: bool = False, 
                verbose: bool = False) -> bool:
    """Run a command with proper logging and error handling."""
    from .config import VERBOSE
    
    if verbose or VERBOSE or show_output:
        print_info(f"Running: {' '.join(cmd)}")
        print_info(f"Working directory: {cwd}")
    
    # Merge environment
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    
    # Open log file if specified
    log_handle = None
    if log_file:
        log_handle = open(log_file, 'a')
        log_handle.write(f"\n{'='*60}\n")
        log_handle.write(f"Command: {' '.join(cmd)}\n")
        log_handle.write(f"Working directory: {cwd}\n")
        log_handle.write(f"{'='*60}\n")
        log_handle.flush()
    
    try:
        process = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=full_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )
        
        # Stream output
        for line in process.stdout:
            if show_output or VERBOSE or verbose:
                print(line.rstrip())
            if log_handle:
                log_handle.write(line)
                log_handle.flush()
        
        process.wait()
        
        if log_handle:
            log_handle.write(f"\nReturn code: {process.returncode}\n")
            log_handle.close()
        
        return process.returncode == 0
    
    except Exception as e:
        print_error(f"Command failed: {e}")
        if log_handle:
            log_handle.write(f"\nException: {e}\n")
            log_handle.close()
        return False


# =============================================================================
# DIRECTORY MANAGEMENT
# =============================================================================

def create_directories(script_dir: Path, local_prefix: str):
    """Create necessary directories."""
    downloads_dir = script_dir / 'downloads'
    logs_dir = script_dir / 'logs'
    
    downloads_dir.mkdir(exist_ok=True)
    logs_dir.mkdir(exist_ok=True)
    Path(local_prefix).mkdir(parents=True, exist_ok=True)
    
    return downloads_dir, logs_dir


def get_script_directories():
    """Get script directory and related paths."""
    # Get the directory where the main script is located
    # This works whether called from build-tools script or imported
    import __main__
    if hasattr(__main__, '__file__'):
        script_dir = Path(__main__.__file__).parent.absolute()
    else:
        # Fallback to current working directory
        script_dir = Path.cwd()
    
    return script_dir


# =============================================================================
# ENVIRONMENT MANAGEMENT
# =============================================================================

def get_build_env(tools_built: List[str], local_prefix: str, make_jobs: int) -> Dict[str, str]:
    """Get environment variables for building, using previously built tools."""
    env = {}
    
    # Build PATH with previously built tools
    paths = []
    for tool in tools_built:
        tool_bin = Path(local_prefix) / tool / 'bin'
        if tool_bin.exists():
            paths.append(str(tool_bin))
    
    if paths:
        current_path = os.environ.get('PATH', '')
        env['PATH'] = ':'.join(paths + [current_path])
    
    # Set other important variables
    env['MAKEFLAGS'] = f'-j{make_jobs}'
    
    return env


def print_build_summary(local_prefix: str, tools: List[str]):
    """Print build completion summary with usage instructions."""
    print_success("Build completed successfully!")
    print_info("Add the following to your ~/.bashrc to use the new tools:")
    
    for tool in tools:
        tool_bin = Path(local_prefix) / tool / 'bin'
        if tool_bin.exists():
            print_info(f"export PATH={tool_bin}:$PATH")
        else:
            print_warning(f"Tool directory not found: {tool_bin}")


def print_configuration_summary(config_data: dict):
    """Print current configuration summary."""
    print_info("Build Tools Configuration")
    for key, value in config_data.items():
        print_info(f"{key}: {value}")