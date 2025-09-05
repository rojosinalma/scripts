"""
Download and extraction functionality for build-tools.

This module handles downloading source archives from mirrors,
extracting them, and managing the downloads directory.
"""

import tarfile
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional

from .utils import print_info, print_success, print_error, print_warning


def download_file(url: str, dest: Path, show_progress: bool = True) -> bool:
    """Download a file with progress indication."""
    if dest.exists():
        print_info(f"File already exists: {dest.name}")
        return True
    
    try:
        print_info(f"Downloading {dest.name}...")
        
        def progress_hook(block_num, block_size, total_size):
            if show_progress and total_size > 0:
                percent = min(100, block_num * block_size * 100 / total_size)
                print(f"\r  Progress: {percent:.1f}%", end='', flush=True)
        
        urllib.request.urlretrieve(url, dest, progress_hook if show_progress else None)
        
        if show_progress:
            print()  # New line after progress
        print_success(f"Downloaded {dest.name}")
        return True
    
    except Exception as e:
        print_error(f"Failed to download {url}: {e}")
        if dest.exists():
            dest.unlink()  # Remove partial download
        return False


def extract_archive(archive: Path, dest_dir: Path) -> Optional[Path]:
    """Extract tar.gz archive and return the extracted directory path."""
    if not archive.exists():
        print_error(f"Archive not found: {archive}")
        return None
    
    print_info(f"Extracting {archive.name}...")
    
    try:
        with tarfile.open(archive, 'r:gz') as tar:
            # Get the top-level directory name
            members = tar.getnames()
            if not members:
                print_error(f"Empty archive: {archive}")
                return None
            
            top_dir = members[0].split('/')[0]
            extracted_path = dest_dir / top_dir
            
            if extracted_path.exists():
                print_info(f"Directory already exists: {top_dir}")
                return extracted_path
            
            tar.extractall(dest_dir)
            print_success(f"Extracted {archive.name}")
            return extracted_path
    
    except Exception as e:
        print_error(f"Failed to extract {archive}: {e}")
        return None


def download_sources(urls: Dict[str, str], downloads_dir: Path) -> bool:
    """Download all source archives."""
    print_info("Downloading source archives...")
    
    success = True
    for tool, url in urls.items():
        filename = url.split('/')[-1]
        dest = downloads_dir / filename
        if not download_file(url, dest):
            success = False
            print_error(f"Failed to download {tool}")
    
    if success:
        print_success("All sources downloaded successfully")
    else:
        print_error("Some downloads failed")
    
    return success


def download_specific_source(tool: str, urls: Dict[str, str], downloads_dir: Path) -> bool:
    """Download source archive for a specific tool."""
    if tool not in urls:
        print_error(f"Unknown tool: {tool}")
        return False
    
    url = urls[tool]
    filename = url.split('/')[-1]
    dest = downloads_dir / filename
    
    return download_file(url, dest)


def check_sources_exist(tools: List[str], versions: Dict[str, str], downloads_dir: Path) -> Dict[str, bool]:
    """Check which source archives already exist."""
    status = {}
    
    for tool in tools:
        version = versions[tool]
        filename = f"{tool}-{version}.tar.gz"
        archive_path = downloads_dir / filename
        status[tool] = archive_path.exists()
    
    return status


def clean_downloads(downloads_dir: Path, keep_patterns: List[str] = None) -> int:
    """Clean up downloads directory, optionally keeping files matching patterns."""
    if not downloads_dir.exists():
        return 0
    
    count = 0
    for item in downloads_dir.iterdir():
        if item.is_file():
            should_keep = False
            if keep_patterns:
                for pattern in keep_patterns:
                    if pattern in item.name:
                        should_keep = True
                        break
            
            if not should_keep:
                item.unlink()
                count += 1
        elif item.is_dir():
            # Remove extracted directories
            import shutil
            shutil.rmtree(item)
            count += 1
    
    if count > 0:
        print_info(f"Cleaned up {count} items from downloads directory")
    
    return count