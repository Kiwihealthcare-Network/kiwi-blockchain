import nest_asyncio
from pkg_resources import DistributionNotFound, get_distribution, resource_filename

nest_asyncio.apply()

try:
    # charles 20220314 change version to kiwi-blockchain
    # __version__ = get_distribution("chia-blockchain").version
    __version__ = get_distribution("kiwi-blockchain").version
except DistributionNotFound:
    # package is not installed
    __version__ = "unknown"

PYINSTALLER_SPEC_PATH = resource_filename("chia", "pyinstaller.spec")
