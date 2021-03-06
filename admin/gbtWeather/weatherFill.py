# Copyright (C) 2011 Associated Universities, Inc. Washington DC, USA.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# Correspondence concerning GBT software should be addressed as follows:
#       GBT Operations
#       National Radio Astronomy Observatory
#       P. O. Box 2
#       Green Bank, WV 24944-0002 USA

import TimeAgent
from datetime     import datetime
import sys


"""
This script accepts weather simulation files as generated by Dana Balser
in the specified directory. Each file consists of text where each row
consists of the following columns:

  0: MJD time (on the hour spacing)
  1: measured median wind speed over one hour (weather station #2)
  2: maximum measured median wind speed of 20-sec chunks over one hour
     (weather station #2)
  3: 90th percentile of the measured median wind speed of 20-sec chunks
     over one hour (weather station #2)
  4: forecasted wind speed (raw data from CLEO weather forecaster)
  5: forecasted opacity (tau) @ 2 GHz
  6: forecasted kinetic atmospheric temperature (Tk) @ 2 GHz
  7: forecasted opacity (tau) @ 3 GHz
  8: forecasted kinetic atmospheric temperature (Tk) @ 3 GHz
               .
               .
               .
  101: forecasted opacity (tau) @ 50 GHz
  102: forecasted kinetic atmospheric temperature (Tk) @ 50 GHz

Resulting in 103 columns.  Note that some hours (rows) are missing yielding
fewer than 365*24 + 1 rows.

It writes the data to the matching files in the specified directory
except it truncates the list to first and last hour of the year
and interpolates all missing hours.  Since time as an offset is
implied by the row, the MJD column is dropped resulting in 102 columns.
"""

PREFIX       = 'simulateTime_2006_'
SUFFIXES     = ['0-11',  '12-23', '24-35', '36-47', '48-59']
STARTDATE    = datetime(2006, 1, 1)

def fill(read_dir, write_dir):
    for suffix in SUFFIXES:
        filename = ''.join([PREFIX, suffix, '.txt'])
        readpath = ''.join([read_dir, '/', filename])
        print readpath
        writepath = ''.join([write_dir, '/', filename])
        data = readFileData(readpath)
        data = fillInYear(data)
        writeFileData(writepath, data)


def fillInYear(data):
    retval = []
    i = 0;
    a = i
    #for hour in range(24*30):
    for hour in range(24*365 + 1):
        # Have data for this hour?
        if hour == data[i][0]:
            # just copy it
            retval.append(data[i])
            # move on to the next data row
            i += 1
        else:
            # interpolate between the last data row and the current
            row = [hour]
            row.extend([interpolate(hour,
                                    data[i-1][0],   data[i][0],
                                    data[i-1][col], data[i][col])
                        for col in range(1, len(data[0]))])
            retval.append(row)
    return retval

def readFileData(path):
    data = []
    file = open(path, 'r')
    line = file.readline()
    while line:
        row = [float(field) for field in line.split()]
        row[0] = mjd2offset(row[0])
        data.append(row)
        line = file.readline()
    for i, line in enumerate(data):
        if line[0] >= 0:
            break
    file.close()
    return data[i:]

def writeFileData(path, data):
    file = open(path, 'w')
    for row in data:
        file.write(' '.join([str(v) for v in row[1:]]) + '\n')
    file.close()

def interpolate(x, xa, xb, ya, yb):
    """
    Given known points on the line at (xa, ya) and (xb, yb) then for any 
    point (x, y) on the line we get:
    """
    return ya + ((x - xa) * (yb - ya))/float(xb - xa)

def mjd2offset(mjd):
    return TimeAgent.timedelta2hours(TimeAgent.mjd2dt(mjd) - STARTDATE)
    


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print >>sys.stderr, "Usage: python utilities/weatherFill.py <read_directory> <write_directory>"
        exit()
    fill(sys.argv[1], sys.argv[2])
    
