#  _____ _____ _____
# |_    |   __| __  |
# |_| | |__   |    -|
# |_|_|_|_____|__|__|
# MSR Electronics GmbH
#

from ft4222.cftd2xx cimport *
from ft4222.clibft4222 cimport *
from cpython.array cimport array, resize
from libc.stdio cimport printf


__ftd2xx_msgs = ['OK', 'INVALID_HANDLE', 'DEVICE_NOT_FOUND', 'DEVICE_NOT_OPENED',
                 'IO_ERROR', 'INSUFFICIENT_RESOURCES', 'INVALID_PARAMETER',
                 'INVALID_BAUD_RATE', 'DEVICE_NOT_OPENED_FOR_ERASE',
                 'DEVICE_NOT_OPENED_FOR_WRITE', 'FAILED_TO_WRITE_DEVICE0',
                 'EEPROM_READ_FAILED', 'EEPROM_WRITE_FAILED', 'EEPROM_ERASE_FAILED',
                 'EEPROM_NOT_PRESENT', 'EEPROM_NOT_PROGRAMMED', 'INVALID_ARGS',
                 'NOT_SUPPORTED', 'OTHER_ERROR', 'DEVICE_LIST_NOT_READY']

__ftd4222_msgs = ['DEVICE_NOT_SUPPORTED', 'CLK_NOT_SUPPORTED','VENDER_CMD_NOT_SUPPORTED',
                  'IS_NOT_SPI_MODE', 'IS_NOT_I2C_MODE', 'IS_NOT_SPI_SINGLE_MODE',
                  'IS_NOT_SPI_MULTI_MODE', 'WRONG_I2C_ADDR', 'INVAILD_FUNCTION',
                  'INVALID_POINTER', 'EXCEEDED_MAX_TRANSFER_SIZE', 'FAILED_TO_READ_DEVICE',
                  'I2C_NOT_SUPPORTED_IN_THIS_MODE', 'GPIO_NOT_SUPPORTED_IN_THIS_MODE',
                  'GPIO_EXCEEDED_MAX_PORTNUM', 'GPIO_WRITE_NOT_SUPPORTED',
                  'GPIO_PULLUP_INVALID_IN_INPUTMODE', 'GPIO_PULLDOWN_INVALID_IN_INPUTMODE',
                  'GPIO_OPENDRAIN_INVALID_IN_OUTPUTMODE', 'INTERRUPT_NOT_SUPPORTED',
                  'GPIO_INPUT_NOT_SUPPORTED', 'EVENT_NOT_SUPPORTED', 'FUN_NOT_SUPPORT']


# Revision A chips report chipVersion as 0x42220100; revision B chips report
# 0x42220200; revision C chips report 0x42220300. Revision B chips require
# version 1.2 or later of LibFT4222, indicated by dllVersion being greater than
# 0x01020000; Revision C chips require version 1.3 or later of LibFT4222, indicated
# by dllVersion being greater than 0x01030000.
__chip_rev_map = { 0x42220100: "Rev. A", 0x42220200: "Rev. B", 0x42220300: "Rev. C" }
__chip_rev_min_lib = { 0x42220100: 0, 0x42220200: 0x01020000, 0x42220300: 0x01030000 }


DEF MAX_DESCRIPTION_SIZE = 256

class FT2XXDeviceError(Exception):
    """Exception class for status messages"""
    def __init__(self, msgnum):
        self.message = __ftd2xx_msgs[msgnum]

    def __str__(self):
        return self.message

class FT4222DeviceError(FT2XXDeviceError):
    """Exception class for status messages"""
    def __init__(self, msgnum):
        if msgnum >= FT4222_DEVICE_NOT_SUPPORTED:
            self.message = __ftd4222_msgs[msgnum - FT4222_DEVICE_NOT_SUPPORTED]
        else:
            super(FT4222DeviceError, self).__init__(msgnum)

    def __str__(self):
        return self.message

def createDeviceInfoList():
    """Create the internal device info list and return number of entries"""
    cdef DWORD nb
    status = FT_CreateDeviceInfoList(&nb)
    if status == FT_OK:
        return nb
    raise FT2XXDeviceError, status

def getDeviceInfoDetail(devnum=0, update=True):
    """Get an entry from the internal device info list. Set update to
    False to avoid a slow call to createDeviceInfoList."""
    cdef:
        DWORD f, t, i, l
        FT_HANDLE h
        char n[MAX_DESCRIPTION_SIZE]
        char d[MAX_DESCRIPTION_SIZE]
    # createDeviceInfoList is slow, only run if update is True
    if update: createDeviceInfoList()
    status = FT_GetDeviceInfoDetail(devnum, &f, &t, &i, &l, n, d, &h)
    if status == FT_OK:
        return {'index': devnum, 'flags': f, 'type': t,
                'id': i, 'location': l, 'serial': n,
                'description': d, 'handle': <size_t>h}
    raise FT2XXDeviceError, status

def openBySerial(serial):
    """Open a handle to a usb device by serial number"""
    cdef FT_HANDLE handle
    cdef char* cserial = serial
    status = FT_OpenEx(<PVOID>cserial, FT_OPEN_BY_SERIAL_NUMBER, &handle)
    if status == FT_OK:
        return FT4222(<uintptr_t>handle, update=False)
    raise FT2XXDeviceError, status

def openByDescription(desc):
    """Open a handle to a usb device by description

    Args:
        desc (bytes, str): Description of the device

    Returns:
        FT4222: Opened device

    Raises:
        FT2XXDeviceError: on error

    """
    if isinstance(desc, str):
        desc = desc.encode('utf-8')
    cdef FT_HANDLE handle
    cdef char* cdesc = desc
    status = FT_OpenEx(<PVOID>cdesc, FT_OPEN_BY_DESCRIPTION, &handle)
    if status == FT_OK:
        #printf("handle: %d\n", handle)
        return FT4222(<uintptr_t>handle, update=False)
    raise FT2XXDeviceError, status

def openByLocation(locId):
    """Open a handle to a usb device by location

    Args:
        locId (int): Location id

    Returns:
        FT4222: Opened device

    Raises:
        FT2XXDeviceError: on error

    """
    cdef FT_HANDLE handle
    status = FT_OpenEx(<PVOID><uintptr_t>locId, FT_OPEN_BY_LOCATION, &handle)
    if status == FT_OK:
        return FT4222(<uintptr_t>handle, update=False)
    raise FT2XXDeviceError, status


cdef class FT4222:
    cdef FT_HANDLE handle
    cdef DWORD chip_version
    cdef DWORD dll_version

    def __init__(self, handle, update=True):
        self.handle = <FT_HANDLE><uintptr_t>handle
        self.chip_version = 0
        self.dll_version = 0
        self.__get_version()

    def __del__(self):
        if self.handle != NULL:
            FT_Close(self.handle)

    def close(self):
        """Closes the device."""
        status = FT_Close(self.handle)
        if status != FT_OK:
            raise FT4222DeviceError, status
        self.handle = NULL

    cdef __get_version(self):
        cdef FT4222_Version ver
        status = FT4222_GetVersion(self.handle, &ver)
        if status == FT4222_OK:
            self.chip_version = ver.chipVersion
            self.dll_version = ver.dllVersion

    @property
    def chipVersion(self) -> int:
        """Chip version as number"""
        return self.chip_version

    @property
    def libVersion(self) -> int:
        """Library version as number"""
        return self.dll_version

    def chipRevision(self) -> str:
        """Get the revision of the chip in human readable format

        Returns:
            str: chip revision

        """
        try:
            return __chip_rev_map[self.chip_version]
        except KeyError:
            return "Rev. unknown"

    def __repr__(self):
        return "FT4222: chipVersion: 0x{:x} ({:s}), libVersion: 0x{:x}".format(self.chip_version, self.chipRevision(), self.dll_version)

    def i2cMaster_Init(self, kbps=100):
        """Initialize the FT4222H as an I2C master with the requested I2C speed.

        Args:
            kbps (int): Speed in kb/s

        Raises:
            FT4222DeviceError: on error

        """
        status = FT4222_I2CMaster_Init(self.handle, kbps)
        if status != FT4222_OK:
            raise FT4222DeviceError, status

    def i2cMaster_Read(self, addr, bytesToRead):
        """Read data from the specified I2C slave device with START and STOP conditions.

        Args:
            addr (int): I2C slave address
            bytesToRead (int): Number of bytes to read from slave

        Returns:
            bytes: Bytes read from slave

        Raises:
            FT4222DeviceError: on error

        """
        cdef:
            array[uint8] buf = array('B', [])
            uint16 bytesRead
        resize(buf, bytesToRead)
        status = FT4222_I2CMaster_Read(self.handle, addr, buf.data.as_uchars, bytesToRead, &bytesRead)
        resize(buf, bytesRead)
        if status == FT4222_OK:
            return bytes(buf)
        raise FT4222DeviceError, status

    def i2cMaster_Write(self, addr, data):
        """Write data to the specified I2C slave device with START and STOP conditions.

        Args:
            addr (int): I2C slave address
            data (int, bytes, bytearray): Data to write to slave

        Returns:
            int: Bytes sent to slave

        Raises:
            FT4222DeviceError: on error

        """
        if isinstance(data, int):
            data = bytes([data])
        elif not isinstance(data, (bytes, bytearray)):
            raise TypeError("the data argument must be of type 'int', 'bytes' or 'bytearray'")
        cdef:
            uint16 bytesSent
            uint8* cdata = data
        status = FT4222_I2CMaster_Write(self.handle, addr, cdata, len(data), &bytesSent)
        if status == FT4222_OK:
            return bytesSent
        raise FT4222DeviceError, status

    def i2cMaster_ReadEx(self, addr, flag, bytesToRead):
        """Read data from the specified I2C slave device with the specified I2C condition.

        Args:
            addr (int): I2C slave address
            flag (ft4222.I2CMaster.Flag): Flag to control start- and stopbit generation
            bytesToRead (int): Number of bytes to read from slave

        Returns:
            bytes: Bytes read from slave

        Raises:
            FT4222DeviceError: on error

        """
        cdef:
            array[uint8] buf = array('B', [])
            uint16 bytesRead
        resize(buf, bytesToRead)
        status = FT4222_I2CMaster_ReadEx(self.handle, addr, flag, buf.data.as_uchars, bytesToRead, &bytesRead)
        resize(buf, bytesRead)
        if status == FT4222_OK:
            return bytes(buf)
        raise FT4222DeviceError, status

    def i2cMaster_WriteEx(self, addr, flag, data):
        """Write data to the specified I2C slave device with the specified I2C condition.

        Args:
            addr (int): I2C slave address
            flag (ft4222.I2CMaster.Flag): Flag to control start- and stopbit generation
            data (int, bytes, bytearray): Data to write to slave

        Returns:
            int: Bytes sent to slave

        Raises:
            FT4222DeviceError: on error

        """
        if isinstance(data, int):
            data = bytes([data])
        elif not isinstance(data, (bytes, bytearray)):
            raise TypeError("the data argument must be of type 'int', 'bytes' or 'bytearray'")
        cdef:
            uint16 bytesSent
            uint8* cdata = data
        status = FT4222_I2CMaster_WriteEx(self.handle, addr, flag, cdata, len(data), &bytesSent)
        if status == FT4222_OK:
            return bytesSent
        raise FT4222DeviceError, status

    def i2cMaster_Reset(self):
        """Reset the I2C master device.

        If the I2C bus encounters errors or works abnormally, this function will reset the I2C device.
        It is not necessary to call I2CMaster_Init again after calling this reset function.
        """
        status = FT4222_I2CMaster_Reset(self.handle)
        if status != FT4222_OK:
            raise FT4222DeviceError, status

    def i2cMaster_GetStatus(self):
        """Read the status of the I2C master controller.

        This can be used to poll a slave until its write-cycle is complete.

        Returns:
            ft4222.I2CMaster.ControllerStatus: Controller status
        """
        cdef uint8 cs
        status = FT4222_I2CMaster_GetStatus(self.handle, &cs)
        if status == FT4222_OK:
            return cs
        raise FT4222DeviceError, status

