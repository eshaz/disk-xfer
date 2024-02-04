disk-xfer
---------

A simple pair of programs to image copy an MS-DOS hard drive to an image file on a remote computer over serial port.

I wrote this because I needed a quick tool to back up a Conner CP-30104H disk from a GRiDCASE 1537, and nothing else was working.

If you find it useful, that's awesome.

to use:

Start tx on source machine:

```
C> tx
```

Start rx on destination machine:

```
$ rx diskimage.img
```

If everything is connected correctly, tx will send the data over the COM1: serial port to the destination machine in the requested image file.

## Developing

### Prerequisites
* Linux build environment
* `make gcc dosbox`

### Build `rx` and `tx`
```sh
make
```

### Formatting
```sh
make format
```

## Using Drivers for faster baud rates

### ADF driver (Recommended)
* Installing this driver allows the serial port to operate at higher baud rates up to `115200`.
* You need to load the driver prior to running `tx`
* Copy the below files to your boot disk to install ADF on boot
  * [ADF.EXE](tx-msdos/drivers/adf/bin/ADF.EXE)
  * [AUTOEXEC.BAT](tx-msdos/drivers/adf/AUTOEXEC.BAT)
  * [ADFCOM1.BAT](tx-msdos/drivers/adf/ADFCOM1.BAT)
* To change the baud rate, you need to edit `ADFCOM1.BAT` to change the default parameters
  * `115200` is set as the default baud rate
  * The baud rate cannot be set using `tx` with this driver.

### X00 driver
* Installing this driver allows the serial port to operate at higher baud rates up to `38400`.
* You need to boot DOS with the driver to running `tx`
* Copy the below files to your boot disk to install X00 on boot
  * [X00.SYS](tx-msdos/drivers/x00/X00.SYS)
  * [CONFIG.SYS](tx-msdos/drivers/x00/autoexec.bat)
* You may set the desired baud rate when running `tx`
  * i.e. `tx 0 38400`

### No Drivers
* Making disk images without installing a FOSSIL driver is not supported.

