# Steps in creating a new dss_unit_tests for antioch:
# 
# The database dss_unit_tests is used for unit tests in DSSDataTests
# and ReceiverTemperaturesTests.
# 
# Call the new database in this example new_dss_unit_tests.
# 
# 1) Run: createdb -U dss new_dss_unit_tests
# 
# 2) In directory nell:
#     Modify settings.py such that DATABASE_NAME equals 'new_dss_unit_tests'
#     Run: python manage.py syncdb
#       reply no to question "Would you like to create one now? (yes/no):"
#     Run: psql -U dss new_dss_unit_tests <populate_db.sql
# 3) In directory antioch/admin:
#     Run: updateRcvrTemps new_dss_unit_tests
# 4) In directory nell:
#     Copy: cp antioch/admin/genDssTestDatabase.py admin
#     Run: python admin/genDssTestDatabase.py
# 5) In directory antioch:
#     Modify src/Antioch/Settings.lhs such that hardwareScheduleDB and
#     dssDataDB equals "new_dss_unit_tests".
#     Test and develop old and new unit tests.

from django.core.management    import setup_environ
import settings
setup_environ(settings)

from datetime                  import datetime
from sesshuns.models           import *
from nell.tools.TimeAccounting import TimeAccounting

def create_project(fdata):
    project = Project()
    fproj_type = fdata.get("type", "science")
    p_type     = first(Project_Type.objects.filter(type = fproj_type))
    fsemester  = fdata.get("semester", "09C")
    semester   = first(Semester.objects.filter(semester = fsemester))

    project.semester         = semester
    project.project_type     = p_type
    project.pcode            = fdata.get("pcode", "")
    project.name             = fdata.get("name", "")
    project.thesis           = fdata.get("thesis", "false") == "true"
    project.complete         = fdata.get("complete", "false") == "true"
    project.save()

    a = Allotment(psc_time          = fdata.get("PSC_time", 0.0)
                , total_time        = fdata.get("total_time", 0.0)
                , max_semester_time = fdata.get("sem_time", 0.0)
                , grade             = fdata.get("grade", 4.0)
                  )
    a.save()
    pa = Project_Allotment(project = project, allotment = a)
    pa.save()

    if fdata.has_key("grade_2"):
        a = Allotment(psc_time          = fdata.get("PSC_time_2", 0.0)
                    , total_time        = fdata.get("total_time_2", 0.0)
                    , max_semester_time = fdata.get("sem_time_2", 0.0)
                    , grade             = fdata.get("grade_2", 3.0)
                      )
        a.save()
        pa = Project_Allotment(project = project, allotment = a)
        pa.save()

    project.save() # TBF needed?
    return project

def create_lst_exclusion(sesshun, fdata):
    """
    Converts the json representation of the LST exclude flag
    to the model representation.
    """
    lowParam = first(Parameter.objects.filter(name="LST Exclude Low"))
    hiParam  = first(Parameter.objects.filter(name="LST Exclude Hi"))
    
    # json dict string representation
    lst_ex_string = fdata.get("lst_ex", None)
    if not lst_ex_string:
        return

    # unwrap and get the float values
    lowStr, highStr = lst_ex_string.split("-")
    low = float(lowStr)
    high = float(highStr)
    assert low <= high

    # create a new LST Exlusion range
    obs_param =  Observing_Parameter(session = sesshun
                                   , parameter = lowParam
                                   , float_value = low 
                                    )
    obs_param.save()
    obs_param =  Observing_Parameter(session = sesshun
                                   , parameter = hiParam
                                   , float_value = high 
                                    )
    obs_param.save()

def save_receivers(sesshun, proposition):
    abbreviations = [r.abbreviation for r in Receiver.objects.all()]
    # TBF catch errors and report to user
    rc = ReceiverCompile(abbreviations)
    ands = rc.normalize(proposition)
    for ors in ands:
        rg = Receiver_Group(session = sesshun)
        rg.save()
        for rcvr in ors:
            rcvrId = Receiver.objects.filter(abbreviation = rcvr)[0]
            rg.receivers.add(rcvrId)
            rg.save()

def get_field(fdata, key, defaultValue, cast):
    "Some values from the dict we know we need to type cast"
    value = fdata.get(key, defaultValue)
    if cast != bool:
        return value if value is None else cast(value)
    else:
        return value == "true"

def create_session(sesshun, project, fdata):
    "Utility method for creating a Sesshun to test."

    fsestype = fdata.get("type", "open")
    fobstype = fdata.get("science", "testing")
    proj_code = fdata.get("pcode", "Test-Project")

    st = first(Session_Type.objects.filter(type = fsestype).all()
             , Session_Type.objects.all()[0])
    ot = first(Observing_Type.objects.filter(type = fobstype).all()
             , Observing_Type.objects.all()[0])

    sesshun.project          = project
    sesshun.session_type     = st
    sesshun.observing_type   = ot
    sesshun.original_id      = 0
    sesshun.name             = fdata.get("name", None)
    sesshun.frequency        = fdata.get("freq", None)
    sesshun.max_duration     = TimeAgent.rndHr2Qtr(float(fdata.get("req_max", 12.0)))
    sesshun.min_duration     = TimeAgent.rndHr2Qtr(float(fdata.get("req_min",  3.0)))
    sesshun.time_between     = fdata.get("between", None)

    allot = Allotment(psc_time          = fdata.get("PSC_time", 0.0)
                    , total_time        = fdata.get("total_time", 0.0)
                    , max_semester_time = fdata.get("sem_time", 0.0)
                    , grade             = fdata.get("grade", 4.0)
                      )
    allot.save()
    sesshun.allotment        = allot

    status = Status(
               enabled    = get_field(fdata, "enabled", True, bool)
             , authorized = get_field(fdata, "authorized", True, bool)
             , complete   = get_field(fdata, "complete", True, bool) 
             , backup     = get_field(fdata, "backup", True, bool) 
                    )
    status.save()
    sesshun.status = status
    sesshun.save()

    create_lst_exclusion(sesshun, fdata)
    
    proposition = fdata.get("receiver")
    save_receivers(sesshun, proposition)
    
    systemName = fdata.get("coord_mode", "J2000")
    system = first(System.objects.filter(name = systemName).all()
                 , System.objects.all()[0])

    v_axis = fdata.get("source_v", 0.0)
    h_axis = fdata.get("source_h", 0.0)
    
    target = Target(session    = sesshun
                  , system     = system
                  , source     = fdata.get("source", None)
                  , vertical   = v_axis
                  , horizontal = h_axis
                    )
    target.save()
    sesshun.save()

    return sesshun

def create_window(sesshun, fdata):
    window = Window()
    window.session = sesshun
    window.total_time = fdata.get("total_time", 0.0)
    window.complete = fdata.get("complete", False)

    window.save()
    wr = WindowRange()
    wr.start_date = fdata.get("start_date",
                                  datetime(2006, 5, 11, 0, 0, 0))
    wr.duration = fdata.get("duration", 7)
    wr.window = window
    wr.save()
    
    return window

def create_period(sesshun, fdata):
    period = Period()
    period.score = 0.0
    period.forecast = fdata.get("forecast", datetime(2006, 5, 11, 4, 15, 0))
    period.session = sesshun
    period.start = fdata.get("start", datetime(2006, 5, 11, 12, 0, 0))
    period.duration = fdata.get("duration", 1.0)
    stateAbbr = fdata.get("state", "P")
    period.state = first(Period_State.objects.filter(abbreviation=stateAbbr))
    window = fdata.get("window", None)
    period.window_id = window.id if window is not None else None
    elective = fdata.get("elective", None)
    period.elective_id = elective.id if elective is not None else None
    pa = Period_Accounting(scheduled = 0.0)
    pa.save()
    period.accounting = pa

    period.save()
    return period

def create_receiver_schedule():
    receiver_schedule = [
      Receiver_Schedule(receiver_id=8, start_date=datetime(2009, 5, 30, 0, 0))
    , Receiver_Schedule(receiver_id=10, start_date=datetime(2009, 5, 30, 0, 0))
    , Receiver_Schedule(receiver_id=11, start_date=datetime(2009, 5, 30, 0, 0))
    , Receiver_Schedule(receiver_id=2, start_date=datetime(2009, 5, 30, 0, 0))
    , Receiver_Schedule(receiver_id=8, start_date=datetime(2009, 6, 4, 16, 0))
    , Receiver_Schedule(receiver_id=10, start_date=datetime(2009, 6, 4, 16, 0))
    , Receiver_Schedule(receiver_id=11, start_date=datetime(2009, 6, 4, 16, 0))
    , Receiver_Schedule(receiver_id=12, start_date=datetime(2009, 6, 4, 16, 0))
    , Receiver_Schedule(receiver_id=7, start_date=datetime(2009, 6, 4, 16, 0))
    , Receiver_Schedule(receiver_id=8, start_date=datetime(2009, 6, 10, 16, 0))
    , Receiver_Schedule(receiver_id=10, start_date=datetime(2009, 6, 10, 16, 0))
    , Receiver_Schedule(receiver_id=11, start_date=datetime(2009, 6, 10, 16, 0))
    , Receiver_Schedule(receiver_id=12, start_date=datetime(2009, 6, 10, 16, 0))
    , Receiver_Schedule(receiver_id=3, start_date=datetime(2009, 6, 10, 16, 0))
    , Receiver_Schedule(receiver_id=8, start_date=datetime(2009, 6, 11, 16, 0))
    , Receiver_Schedule(receiver_id=10, start_date=datetime(2009, 6, 11, 16, 0))
    , Receiver_Schedule(receiver_id=11, start_date=datetime(2009, 6, 11, 16, 0))
    , Receiver_Schedule(receiver_id=12, start_date=datetime(2009, 6, 11, 16, 0))
    , Receiver_Schedule(receiver_id=3, start_date=datetime(2009, 6, 11, 16, 0))
    , Receiver_Schedule(receiver_id=9, start_date=datetime(2009, 6, 11, 16, 0))
    , Receiver_Schedule(receiver_id=8, start_date=datetime(2009, 6, 15, 16, 0))
    , Receiver_Schedule(receiver_id=10, start_date=datetime(2009, 6, 15, 16, 0))
    , Receiver_Schedule(receiver_id=11, start_date=datetime(2009, 6, 15, 16, 0))
    , Receiver_Schedule(receiver_id=12, start_date=datetime(2009, 6, 15, 16, 0))
    , Receiver_Schedule(receiver_id=9, start_date=datetime(2009, 6, 15, 16, 0))
    , Receiver_Schedule(receiver_id=6, start_date=datetime(2009, 6, 15, 16, 0))
    , Receiver_Schedule(receiver_id=9, start_date=datetime(2006, 6, 1, 0, 0))
    , Receiver_Schedule(receiver_id=8, start_date=datetime(2006, 6, 1, 0, 0))
    , Receiver_Schedule(receiver_id=10, start_date=datetime(2006, 6, 7, 0, 0))
    , Receiver_Schedule(receiver_id=8, start_date=datetime(2006, 6, 7, 0, 0))
    ]
    for rs in receiver_schedule:
        rs.save()

def populate_project1():

    #fdata = dict(
    #    type         = "science"
    #  , semester     = "09A"
    #  , pcode        = "GBT09A-001"
    #  , total_time   = 8.0
    #  , PSC_time     = 8.0
    #  , sem_time     = 8.0
    #  , grade        = 4.0
    #  , PSC_time_2   = 4.0
    #  , total_time_2 = 4.0
    #  , sem_time_2   = 2.0
    #  , grade_2      = 3.0
    #  )
    #proj = create_project(fdata)
    proj = Project.objects.get(pcode = "GBT09A-001")
    sess = Sesshun(project = proj)
    fdata = dict(
        type       = "open"
      , science    = "testing"
      , name       = "GBT09A-001-02"
      , freq       = 9.3
      , req_max    =  3.5
      , req_min    =  3.0
      , between    = None
      , PSC_time   = 3.5
      , total_time = 3.5
      , sem_time   = 2.0
      , grade      = 3.0
      , receiver   = u'X'
      , coord_mode = "J2000"
      , source_v   = -0.11362094
      , source_h   = 5.861688
      , source     = "arcturus"
      , lst_ex     = "2.00-4.00"
      )
    create_session(sess, proj, fdata)
    fdata = dict(
        forecast   = datetime(2006, 1, 1, 0, 0, 0)
      , start      = datetime(2006, 1, 1, 0, 0, 0)
      , duration   = 4.0
      , state      = "P"
      )
    create_period(sess, fdata)

    # Windowed session with one Window having a Pending period and
    # a Scheduled period
    sess = Sesshun(project = proj)
    fdata = dict(
        type       = "windowed"
      , science    = "pulsar"
      , name       = "GBT09A-001-03"
      , freq       = 1.4
      , req_max    =  8.0
      , req_min    =  8.0
      , between    = None
      , PSC_time   = 8.0
      , total_time = 8.0
      , sem_time   = 8.0
      , grade      = 4.0
      , receiver   = u'L'
      , coord_mode = "J2000"
      , source_v   = 1.2
      , source_h   = 5.8
      , source     = "0329+54"
      , lst_ex     = None
      )
    create_session(sess, proj, fdata)
    fdata = dict(
        start_date = datetime(2006, 7, 9, 0, 0, 0)
      , duration = 30
      , total_time = 8.0
      , complete = False
      )
    window = create_window(sess, fdata)
    fdata = dict(
        forecast   = datetime(2006, 7, 10, 0, 0, 0)
      , start      = datetime(2006, 7, 10, 0, 0, 0)
      , duration   = 2.0
      , state      = "S"
      , window     = window
      )
    period = create_period(sess, fdata)
    period.accounting.scheduled = period.duration
    period.accounting.save()
    fdata = dict(
        forecast   = datetime(2006, 7, 18, 0, 0, 0)
      , start      = datetime(2006, 7, 18, 0, 0, 0)
      , duration   = 4.0
      , state      = "P"
      , window     = window
      )
    create_period(sess, fdata)
    fdata = dict(
        forecast   = datetime(2006, 8, 8, 0, 0, 0)
      , start      = datetime(2006, 8, 8, 0, 0, 0)
      , duration   = 8.0
      , state      = "P"
      , window     = window
      )
    window.default_period = create_period(sess, fdata)
    window.save()
    # Elective Session w/ one pair of periods
    sess = Sesshun(project = proj)
    fdata = dict(
        type       = "elective"
      , science    = "pulsar"
      , name       = "GBT09A-001-04"
      , freq       = 1.4
      , req_max    =  8.0
      , req_min    =  8.0
      , between    = None
      , PSC_time   = 8.0
      , total_time = 8.0
      , sem_time   = 8.0
      , grade      = 4.0
      , receiver   = u'L'
      , coord_mode = "J2000"
      , source_v   = 1.2
      , source_h   = 5.8
      , source     = "0329+54"
      , lst_ex     = None
      )
    create_session(sess, proj, fdata)
    elective = Elective(session = sess
                      , complete = False
                        )
    elective.save()                        
    fdata = dict(
        forecast   = datetime(2006, 9, 18, 0, 0, 0)
      , start      = datetime(2006, 9, 18, 0, 0, 0)
      , duration   = 4.0
      , state      = "P"
      , elective   = elective
      )
    create_period(sess, fdata)
    fdata = dict(
        forecast   = datetime(2006, 9, 22, 0, 0, 0)
      , start      = datetime(2006, 9, 22, 0, 0, 0)
      , duration   = 4.0
      , state      = "P"
      , elective   = elective
      )
    create_period(sess, fdata)

if __name__ == "__main__":
    create_receiver_schedule()
    populate_project1()

    print "Completed generating DSS unit test data"