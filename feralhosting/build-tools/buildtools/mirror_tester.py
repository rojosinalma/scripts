"""
Mirror testing functionality for build-tools.

This module handles testing mirror speeds and selecting the fastest one.
"""

import time
import urllib.request
from typing import List

from .utils import print_info, print_success, print_warning


def test_mirror_speed(mirror: str, timeout: int = 10) -> float:
    """Test download speed of a mirror by downloading a small test file."""
    # Use a small, commonly available file for testing
    test_url = f"{mirror}/hello/hello-2.12.tar.gz"
    
    try:
        start_time = time.time()
        with urllib.request.urlopen(test_url, timeout=timeout) as response:
            # Read first 1MB to test speed
            chunk_size = 1024 * 1024
            response.read(chunk_size)
        end_time = time.time()
        return end_time - start_time
    except Exception as e:
        print_info(f"Mirror {mirror} failed: {e}")
        return float('inf')


def find_fastest_mirror(mirrors: List[str], timeout: int = 10, force_test: bool = False) -> str:
    """Test all mirrors and return the fastest one."""
    # Cache file to avoid testing mirrors repeatedly
    cache_file = None
    try:
        from pathlib import Path
        import json
        import time
        
        cache_dir = Path.home() / '.cache' / 'build-tools'
        cache_dir.mkdir(parents=True, exist_ok=True)
        cache_file = cache_dir / 'mirror_cache.json'
        
        # Check cache (valid for 24 hours)
        if not force_test and cache_file.exists():
            try:
                with open(cache_file, 'r') as f:
                    cache_data = json.load(f)
                
                cache_age = time.time() - cache_data.get('timestamp', 0)
                if cache_age < 86400:  # 24 hours
                    cached_mirror = cache_data.get('best_mirror')
                    if cached_mirror in mirrors:
                        print_info(f"Using cached fastest mirror: {cached_mirror}")
                        return cached_mirror
            except:
                pass  # Ignore cache errors, fall back to testing
    except:
        pass  # If we can't create cache, just proceed without it
    
    print_info("Testing mirror speeds for optimal download performance...")
    
    best_mirror = mirrors[0]  # Default to first mirror
    best_time = float('inf')
    
    for mirror in mirrors:
        print_info(f"Testing {mirror}...")
        speed = test_mirror_speed(mirror, timeout)
        
        if speed < best_time:
            best_time = speed
            best_mirror = mirror
            print_info(f"  Speed: {speed:.2f}s (current best)")
        elif speed != float('inf'):
            print_info(f"  Speed: {speed:.2f}s")
        else:
            print_warning(f"  Mirror failed or timed out")
    
    # Cache the result
    if cache_file:
        try:
            import time
            import json
            cache_data = {
                'best_mirror': best_mirror,
                'timestamp': time.time(),
                'speed': best_time if best_time != float('inf') else None
            }
            with open(cache_file, 'w') as f:
                json.dump(cache_data, f)
        except:
            pass  # Ignore cache write errors
    
    if best_time != float('inf'):
        print_success(f"Fastest mirror: {best_mirror} ({best_time:.2f}s)")
    else:
        print_warning(f"All mirrors failed, using default: {best_mirror}")
    
    return best_mirror


def validate_mirror(mirror: str) -> bool:
    """Validate that a mirror is accessible."""
    try:
        # Test with a simple HEAD request to the base URL
        request = urllib.request.Request(mirror, method='HEAD')
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status == 200
    except:
        return False