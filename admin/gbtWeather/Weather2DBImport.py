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

from datetime        import datetime, timedelta
from WeatherData     import WeatherData
from PyrgeometerData import PyrgeometerData
import pg
import settings

if __name__ == "__main__":
    import sys

class Weather2DBImport:
    """
    This class contains logic to populate the weather database with
    GBT weather data.
    """

    def __init__(self, dbname = ""):
        self.c           = pg.connect(user = "dss"
                                    , dbname = dbname
                                    , port   = settings.DATABASE_PORT
                                    )
        self.weatherData = WeatherData()
        self.pyrgeometerData = PyrgeometerData()

    def getNeededWeatherDates(self, dt = None):
        """
        Get's those dates that don't have any accompanying weather data.
        """
        if dt is None:
            dt = datetime.utcnow()        
        r = \
            self.c.query("""
                         SELECT id, date
                         FROM weather_dates
                         WHERE id NOT IN (SELECT weather_date_id
                                          FROM gbt_weather)
                               AND date <= '%s'
                         """ % dt)
        return [(row['id'], row['date']) for row in r.dictresult()]

    def getNeededWeatherDatesInRange(self, start, end):
        """
        Get's those dates that don't have any accompanying weather data.
        """
        r = self.c.query("""
                         SELECT id, date
                         FROM weather_dates
                         WHERE id NOT IN (SELECT weather_date_id
                                          FROM gbt_weather)
                               AND date >= '%s'
                               AND date <  '%s'
                         """ % (start, end))
        return [(row['id'], row['date']) for row in r.dictresult()]

    def insert(self, weatherDateId, wind, irradiance):
        """
        Inserts a row of data into the weather table.
        """
        # handle missing data - put in what you can
        windOK = wind and wind == wind
        irradianceOK = irradiance and irradiance == irradiance
        if windOK and irradianceOK:
            query = """
                    INSERT INTO gbt_weather (weather_date_id,wind_speed,irradiance)
                    VALUES (%s, %s, %s)
                    """ % (weatherDateId, wind, irradiance)
        elif windOK and not irradianceOK:
            query = """
                    INSERT INTO gbt_weather (weather_date_id,wind_speed)
                    VALUES (%s, %s)
                    """ % (weatherDateId, wind)
        elif not windOK and irradianceOK:
            query = """
                    INSERT INTO gbt_weather (weather_date_id,irradiance)
                    VALUES (%s, %s)
                    """ % (weatherDateId, irradiance)
        if windOK or irradianceOK:
            self.c.query(query)

    def update(self):
        """
        Looks to see what weather times need updating, then retrieves that
        data from the sampler logs, and finally writes results to DB.
        """
        
        results = []

        # look for any missing data within the last year
        end   = datetime.utcnow()
        start = end - timedelta(days = 365)
        dts = self.getNeededWeatherDatesInRange(start, end)

        for dtId, dtStr in dts:
            dt = datetime.strptime(dtStr, "%Y-%m-%d %H:%M:%S")
            try:
                wind = self.weatherData.getHourDanaMedianSpeeds(dt)
            except:
                continue
            di   = self.pyrgeometerData.getHourMedianDownwardIrradiance(dt)
            results.append((dtId, wind, di))
            self.insert(dtId, wind, di)
        return results    

    def findNullValues(self, column):
        "Who is missing a value?"
        query = """
                SELECT gbt.id, wd.date 
                FROM gbt_weather AS gbt, weather_dates AS wd
                WHERE gbt.%s is NULL AND gbt.weather_date_id = wd.id
                """ % column
        r = self.c.query(query)
        return [(row['id'], row['date']) for row in r.dictresult()]
              
    def updateRow(self, rowId, column, value):
        """
        Updates a row in the weather table with a value.
        """
        query = """
                UPDATE gbt_weather SET %s = %s WHERE id = %d
                """ % (column, value, rowId)
        self.c.query(query)

    def backfill(self, column, callback, test = False):
        """
        Generic method for looking for null values in the weather table,
        and updating those rows with the appropriate value from the 
        sampler logs.
        """

        results = []
        missing = self.findNullValues(column)
        for id, dtStr in missing:
            dt = datetime.strptime(dtStr, "%Y-%m-%d %H:%M:%S")
            v = callback(dt)
            # watch for NaN values
            if v and v == v:
                results.append((id, dtStr, v))
                if not test:
                    self.updateRow(id, column, v)
        return results 
   
    def backfillWind(self, test = False):
        return self.backfill("wind_speed"
                           , self.weatherData.getLastHourMedianWindSpeeds
                           , test)

    
    def backfillIrradiance(self):
        return self.backfill("irradiance"
                   , self.pyrgeometerData.getLastHourMedianDownwardIrradiance)
    

    def backfillReport(self, filename):
        "Backfills the DB, and creates report on results."

        # NOTE: current results for this method: using the weather or
        # or weather_unit_test DB's, since we only have 2006 & 2009 - present
        # data in those, and there is no 2006 pygeometer data, this method
        # only backfills in 2009 - present

        f = open(filename, 'w')
        # wind
        lines = []
        lines.append("Wind Speed\n")
        lines.append("Start (ET): %s\n" % datetime.now())
        results = self.backfillWind()
        for r in results:
            lines.append("%s,%s,%s\n" % (r[0], r[1], r[2]))
        lines.append("End (ET): %s\n" % datetime.now())
        f.writelines(lines)    
        # irradiance
        lines = []
        lines.append("Irradiance\n")
        lines.append("Start (ET): %s\n" % datetime.now())
        results = self.backfillIrradiance()
        for r in results:
            lines.append("%s,%s,%s\n" % (r[0], r[1], r[2]))
        lines.append("End (ET): %s\n" % datetime.now())
        f.writelines(lines)    
        f.close()    
        print "printed report to: ", filename

    def backfillDatabase(self, starttime, endtime):
        """
        Acquires the needed data whose dates that don't have any
        accompanying weather data, and inserts it into the database.
        """
        dts = self.getNeededWeatherDatesInRange(starttime, endtime)
        for dtId, dtStr in dts:
            dt = datetime.strptime(dtStr, "%Y-%m-%d %H:%M:%S")
            # Is there wind data?
            try:
                wind = self.weatherData.getHourDanaMedianSpeeds(dt)
            except:
                continue
            di = self.pyrgeometerData.getHourMedianDownwardIrradiance(dt)
            # Is irradiance a NaN?
            if di != di:
                di = None
            print dt, wind, di
            self.insert(dtId, wind, di)

if __name__ == "__main__":
    print "Reading gbt weather data for database", sys.argv[1]
    w = Weather2DBImport(sys.argv[1])
    w.update()
