class BusstopsController < ApplicationController
  StopData = Struct.new(:value, :needsValidation)
  @@votingMajority = 0.75
  @@validationMinimum = 3
  
  def show
    cookies[:stopid] = params[:id]
    
    ids = (params[:id]).split(/[_&=]/)
    agencyid = ids[0]
    stopid = ids[1]
    @busstop = BusStop.new(StopId: stopid)
    session[:agency_id] = agencyid
    session[:stop_id] = stopid
    
    if(params[:direction])
      session[:bearing] = params[:direction]
    end
    
    showLog = BusStop.usageLogger
    showLog.info("Viewing stop #{agencyid}_#{stopid} at #{Time.now}")
    
    if(session[:device_id])
      showLog.info("Submitted by user #{session[:device_id]}")
    elsif(params[:userid])
      session[:device_id] = params[:userid]
      showLog.info("Accessed by user #{params[:userid]}")
    end

    if(session[:user_email])
      showLog.info("User logged in as #{session[:user_email]}")
    end
    
    showLog.info("")
    
    # Get the array w/ all results
    stopdata = BusStop.find_by_sql("SELECT * FROM " + BusStop.table_name + " WHERE stopid = " + stopid + " AND agencyid = " + agencyid)
    officialstop = BusStop.find_by_sql("SELECT * FROM " + BusStop.table_name + " WHERE stopid = "+stopid+" AND userid = 0 AND agencyid = " + agencyid)
    
    if(stopdata.empty?)
      showLog.info("Stop #{agencyid}_#{stopid} at #{Time.now} not found in database")
      showLog.info("")
      redirect_to '/about/missing' and return
    end
    
    # Get the comment
    if (Comment.find_by_agency_id_and_stop_id(agencyid, stopid) == nil)
      session[:comment] = ""
    else
      session[:comment] = Comment.find_by_agency_id_and_stop_id(agencyid, stopid).info
    end
    
    # Track votes and what we have/don't have
    @busstopAttributes = Hash.new
    @validate = Array.new
    @add = Array.new
    
    # Get array for closures
    closuredata = Closure.find_by_sql("SELECT * FROM " + Closure.table_name + " WHERE stopid = " + stopid + " AND agencyid = " + agencyid + " AND StartDate < UTC_TIMESTAMP() AND EndDate > UTC_TIMESTAMP() ORDER BY DateCreated DESC")
    
    intersections = Hash.new
    BusStop.intersectionPositionValues.each {|x| intersections[x] = 0 }
    
    signs = Hash.new
    BusStop.signTypeValues.each {|x| signs[x] = 0 }

    schedules = Hash.new
    BusStop.scheduleTypeValues.each {|x| schedules[x] = 0 }
    
    insets = Hash.new
    BusStop.curbInsetValues.each {|x| insets[x] = 0 }

    benches = Hash.new
    BusStop.benchCountValues.each {|x| benches[x] = 0 }
	
    shelters = Hash.new
    BusStop.shelterCountValues.each {|x| shelters[x] = 0 }
    
    shelterPlacement = Hash.new
    BusStop.shelterInsetValues.each {|x| shelterPlacement[x] = 0 }
    
    shelterOrientation = Hash.new
    BusStop.shelterOrientationValues.each {|x| shelterOrientation[x] = 0 }
	
    cans = Hash.new
    BusStop.trashCanValues.each {|x| cans[x] = 0 }

    stopdata.each do |stop|
      int = BusStop.intersectionPosition(stop.Intersection)
      intersections[int] = intersections[int] + 1

      stype = BusStop.signType(stop.RteSignType)
      signs[stype] = signs[stype] + 1

      htype = BusStop.scheduleType(stop.SchedHolder)
      schedules[htype] = schedules[htype] + 1

      itype = BusStop.curbInset(stop.InsetFromCurb)
      insets[itype] = insets[itype] + 1
	  
      benchcount = BusStop.benchCount(stop.BenchCount)
      benches[benchcount] = benches[benchcount] + 1
	  
      sheltercount = BusStop.shelterCount(stop.Shelters)
      shelters[sheltercount] = shelters[sheltercount] + 1
      
      shelterPlacementCount = BusStop.shelterPosition(stop.ShelterOffset)
      shelterPlacement[shelterPlacementCount] = shelterPlacement[shelterPlacementCount] + 1
      
      shelterOrientationCount = BusStop.shelterOrientation(stop.ShelterOrientation)
      shelterOrientation[shelterOrientationCount] = shelterOrientation[shelterOrientationCount] + 1
	  
      cancount = BusStop.trashCan(stop.HasCan)
      cans[cancount] = cans[cancount] + 1
      
    end
    
    closedStatus = Closure.closureStatus(closuredata)
    session[:closure] = {}
    session[:closure][:status] = closedStatus[0]
    session[:closure][:reported] = closedStatus[1]
    session[:closure][:enddate] = closedStatus[2]
    #render :text => closedStatus.to_s
    #return
    

    # Clear out any counts of "no opinion"
    intersections.delete("unknown")
    signs.delete("unknown")
    schedules.delete("unknown")
    insets.delete("unknown")
    benches.delete("unknown")
    shelters.delete("unknown")
    shelterPlacement.delete("unknown")
    shelterOrientation.delete("unknown")
    cans.delete("unknown")
    
    #@busstopAttributes[:stop_closed] = StopData.new("false", "false")

    # Information we ONLY get from Metro
    session[:stop_name] = officialstop[0].StopName
    session[:intersection_distance] = officialstop[0].FromCrossCurb
	
    # Calculate things that we collect dynamically
    calculateInfo(signs, :sign_type)
    calculateInfo(intersections, :intersection_pos)
    calculateInfo(schedules, :sched_holder)
    calculateInfo(insets, :curb_inset)
    calculateInfo(shelters, :shelter_count)
    calculateInfo(shelterPlacement, :shelter_offset)
    calculateInfo(shelterOrientation, :shelter_orientation)
    calculateInfo(benches, :bench_count)
    calculateInfo(cans, :can_count)
  end

  def calculateInfo(votingHash, infoSymbol)
    if votingHash.empty? == false     
      majorityValue = votingHash.max_by{|k,v| v}[0]
      count = votingHash.values.inject(0) {|sum,x| sum + x}
      session[infoSymbol] = {}
	  
      if (count == 0)
        session[infoSymbol][:value] = "unknown"
      else
        if (((votingHash[majorityValue] * 1.0 / count) > @@votingMajority) && votingHash[majorityValue] >= @@validationMinimum)
          session[infoSymbol][:value] = majorityValue
          session[infoSymbol][:needs_verification] = "false"
          session[infoSymbol][:votes] = votingHash.to_s
        else
          session[infoSymbol][:value] = majorityValue
          session[infoSymbol][:needs_verification] = "true"
          session[infoSymbol][:votes] = votingHash.to_s
        end
      end
    else
      session[infoSymbol][value] = "unknown"
    end
  end
  
  def tallyNumericalValues(tallyHash, vote)
    if (vote).blank? == false
      if tallyHash.has_key?(vote)
        tallyHash[vote] = tallyHash[vote] + 1
      else
        tallyHash[vote] = 1
      end
    end
  end
  
  def checkDevice() 
    if browser.safari?
      @browser = :safari
    else
      @browser = :other
    end
  end
  
  def update
    ids = (params[:id]).split(/[_&=]/)
    agencyid = ids[0]
    stopid = ids[1]
    
    showLog = BusStop.usageLogger
    showLog.info("Viewing update/verify form for #{agencyid}_#{stopid} at #{Time.now}")
    
    if(session[:device_id])
      showLog.info("Accessed by user #{session[:device_id]}")
    end

    if(session[:user_email])
      showLog.info("User logged in as #{session[:user_email]}")
    end
    
    showLog.info("")
  end
  
  def checkVerifiedForSave(stop)
    if (session[:bearing_code][:needs_verification] == "false" && session[:bearing_code][:value] == stop.BearingCode)
      stop.BearingCode = "unknown"
    end
      
    if (session[:intersection_pos][:needs_verification] == "false" && session[:intersection_pos][:value] == stop.Intersection)
      stop.Intersection = "unknown"
    end
      
    if (session[:sign_type][:needs_verification] == "false" && session[:sign_type][:value] == stop.RteSignType)
      stop.RteSignType = "unknown"
    end
      
    if (session[:curb_inset][:needs_verification] == "false" && session[:curb_inset][:value] == stop.InsetFromCurb)
      stop.InsetFromCurb = "unknown"
    end
      
    if (session[:sched_holder][:needs_verification] == "false" && session[:sched_holder][:value] == stop.SchedHolder)
      stop.SchedHolder = "unknown"
    end
    
    if (session[:shelter_count][:needs_verification] == "false" && session[:shelter_count][:value] == stop.Shelters)
      stop.Shelters = "unknown"
    end
      
    if (session[:bench_count][:needs_verification] == "false" && session[:bench_count][:value] == stop.BenchCount)
      stop.BenchCount = "unknown"
    end
      
    if (session[:can_count][:needs_verification] == "false" && session[:can_count][:value] == stop.HasCan)
      stop.HasCan = "unknown"
    end
  end

  def create
    @busstop = BusStop.new(params[:busstop])
    checkVerifiedForSave(@busstop)
    @busstop.save
    
    @log = Log.new
    @log.input_id = @busstop.InputId
    Log.updateAttributes(@log, session)
    @log.save
    
    showLog = BusStop.usageLogger
    showLog.info("Submitted stop info for #{params[:busstop][:AgencyId]}_#{params[:busstop][:StopId]} at #{Time.now}")
    
    if(session[:device_id])
      showLog.info("Submitted by user #{session[:device_id]}")
    end

    if(session[:user_email])
      showLog.info("User logged in as #{session[:user_email]}")
    end
    
    showLog.info("")
    
    # Don't overwrite our comment with null for not logged in users
    if(session[:user_email])
      Comment.add_or_edit(@busstop.AgencyId, @busstop.StopId, @busstop.StopComment)
    end
    
    redirect_to dataentry_url(:id => params[:busstop][:AgencyId] + "_" + params[:busstop][:StopId])
  end

end