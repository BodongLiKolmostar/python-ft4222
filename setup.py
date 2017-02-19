#   ________________     _________________    ________________
#  /                |   /                 |  |                 \
# |    __     __    |  |    ______________|  |    __________    |
# |   |  |   |  |   |  |   |                 |   |          |   |
# |___|  |___|  |   |  |   |______________   |   |          |   |
#  ___    ___   |   |  |                  |  |   |   _______|   |
# |___|  |   |  |   |  |_____________     |  |   |  |           |
#  ___   |___|  |   |                |    |  |   |  |__     ___/
# |___|   ___   |   |   _____________|    |  |   |     \    \
#  ___   |   |  |   |  |                  |  |   |      \    \
# |___|  |___|  |___|  |_________________/   |___|       \____\
#

from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
    name='pyFT4222',
    version='0.1',
    author='Martin Gysel',
    author_email='me@bearsh.org',
    description='python wrapper around libFT4222',
    ext_modules = cythonize([
        Extension("ft4222", ["ft4222.pyx"],
                  libraries=["ft4222"],
                  extra_compile_args=["-Ilinux"],
                  extra_link_args=["-Llinux/build-x86_64/"])
    ])
)
