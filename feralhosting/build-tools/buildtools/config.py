"""
Configuration and version management for build-tools.

This module handles all configuration variables, version compatibility sets,
and environment variable overrides.
"""

import os
import multiprocessing


# =============================================================================
# CONFIGURATION VARIABLES - Override via environment variables
# =============================================================================

# Installation prefix - where all tools will be installed
LOCAL_PREFIX = os.environ.get('LOCAL_PREFIX', os.path.expanduser('~/tools'))

# GNU mirror for downloading sources
GNU_MIRROR = os.environ.get('GNU_MIRROR', 'https://ftp.gnu.org/gnu')

# Number of parallel make jobs
MAKE_JOBS = int(os.environ.get('MAKE_JOBS', str(multiprocessing.cpu_count())))

# Verbose output flag
VERBOSE = os.environ.get('VERBOSE', '').lower() in ('1', 'true', 'yes')


# Compatibility set selection
COMPAT_SET = os.environ.get('COMPAT_SET', 'latest')

# Individual tool versions (can be overridden)
GCC_VERSION = os.environ.get('GCC_VERSION', '')
BINUTILS_VERSION = os.environ.get('BINUTILS_VERSION', '')
MAKE_VERSION = os.environ.get('MAKE_VERSION', '')
AUTOCONF_VERSION = os.environ.get('AUTOCONF_VERSION', '')
AUTOMAKE_VERSION = os.environ.get('AUTOMAKE_VERSION', '')
LIBTOOL_VERSION = os.environ.get('LIBTOOL_VERSION', '')


# =============================================================================
# VERSION COMPATIBILITY MATRICES
# =============================================================================

COMPATIBILITY_SETS = {
    'latest': {
        'gcc': '14.2.0',
        'binutils': '2.43',
        'make': '4.4.1',
        'autoconf': '2.72',
        'automake': '1.17',
        'libtool': '2.4.7'
    },
    'stable': {
        'gcc': '13.3.0',
        'binutils': '2.42',
        'make': '4.4.1',
        'autoconf': '2.71',
        'automake': '1.16.5',
        'libtool': '2.4.7'
    },
    'legacy': {
        'gcc': '11.4.0',
        'binutils': '2.40',
        'make': '4.4',
        'autoconf': '2.71',
        'automake': '1.16.5',
        'libtool': '2.4.6'
    }
}

# Mirror list for testing
GNU_MIRRORS = [
    'https://ftp.gnu.org/gnu',
    'https://mirrors.kernel.org/gnu',
    'https://mirror.team-cymru.org/gnu',
    'https://ftpmirror.gnu.org',
    'https://gnu.mirror.constant.com'
]

# Build order - defines dependency chain
BUILD_ORDER = [
    'binutils',  # Must be first - provides assembler and linker for GCC
    'gcc',       # Must use new binutils
    'make',      # Built with new GCC
    'autoconf',  # Built with new GCC and make
    'automake',  # Built with new GCC, make, and autoconf
    'libtool'    # Built with all new tools
]


def get_versions():
    """Get versions for all tools based on compatibility set and overrides."""
    if COMPAT_SET not in COMPATIBILITY_SETS:
        raise ValueError(f"Unknown compatibility set: {COMPAT_SET}")
    
    versions = COMPATIBILITY_SETS[COMPAT_SET].copy()
    
    # Override with individual version variables if set
    overrides = {
        'gcc': GCC_VERSION,
        'binutils': BINUTILS_VERSION,
        'make': MAKE_VERSION,
        'autoconf': AUTOCONF_VERSION,
        'automake': AUTOMAKE_VERSION,
        'libtool': LIBTOOL_VERSION
    }
    
    for tool, override_version in overrides.items():
        if override_version:
            versions[tool] = override_version
    
    return versions


def get_tool_urls(versions, mirror):
    """Get download URLs for all tools."""
    return {
        'gcc': f"{mirror}/gcc/gcc-{versions['gcc']}/gcc-{versions['gcc']}.tar.gz",
        'binutils': f"{mirror}/binutils/binutils-{versions['binutils']}.tar.gz",
        'make': f"{mirror}/make/make-{versions['make']}.tar.gz",
        'autoconf': f"{mirror}/autoconf/autoconf-{versions['autoconf']}.tar.gz",
        'automake': f"{mirror}/automake/automake-{versions['automake']}.tar.gz",
        'libtool': f"{mirror}/libtool/libtool-{versions['libtool']}.tar.gz",
    }