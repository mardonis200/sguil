# $Id: SguildSensorCmdRcvd.tcl,v 1.4 2004/10/28 19:49:33 bamm Exp $ #

proc SensorCmdRcvd { socketID } {
  global connectedAgents agentSensorName
  if { [eof $socketID] || [catch {gets $socketID data}] } {
    # Socket closed
    catch { close $socketID } closeError
    InfoMessage "Socket $socketID closed"
    if { [info exists connectedAgents] && [info exists agentSensorName($socketID)] } {
      CleanUpDisconnectedAgent $socketID
    }
  } else {
    InfoMessage "Sensor Data Rcvd: $data"
    # note that ctoken changes the string that it is operating on
    # so instead of re-writing all of the proc to move up one in
    # the index when looking at $data, I wrote $data to $tmpData
    # before using ctoken.  Probably should drop this and fix the
    # procs, but that can happen later
    set tmpData $data
    set sensorCmd [ctoken tmpData " "]
    # set sensorCmd [lindex $data 0]
    switch -exact -- $sensorCmd {
      RTEvent   { EventRcvd $socketID $data }
      PSFile    { RcvPortscanFile $socketID [lindex $data 1] }
      CONNECT   { SensorAgentConnect $socketID [lindex $data 1] }
      DiskReport { $sensorCmd $socketID [lindex $data 1] [lindex $data 2] }
      SsnFile   { RcvSsnFile $socketID [lindex $data 1] [lindex $data 2] [lindex $data 3] }
      PING      { puts $socketID "PONG"; flush $socketID }
      PONG      { SensorAgentPongRcvd $socketID }
      XscriptDebugMsg { $sensorCmd [lindex $data 1] [lindex $data 2] }
      RawDataFile { $sensorCmd $socketID [lindex $data 1] [lindex $data 2] }
      default   { LogMessage "Sensor Cmd Unkown ($socketID): $sensorCmd" }
    }
  }
}

proc RcvSsnFile { socketID tableName fileName sensorName } {
  global TMPDATADIR DBHOST DBPORT DBNAME DBUSER DBPASS loaderWritePipe
  set sensorID [GetSensorID $sensorName]
  InfoMessage "Receiving session file $fileName."
  fconfigure $socketID -translation binary
  set DB_OUTFILE $TMPDATADIR/$fileName
  set fileID [open $DB_OUTFILE w]
  fcopy $socketID $fileID
  close $fileID
  close $socketID
  if {$sensorID == 0} {
      LogMessage "ERROR: $sensorName is not in DB!!"
      SendSystemInfoMsg sguild "ERROR: Received session file from unkown sensor - $sensorName"
      return
  }
  set inFileID [open $DB_OUTFILE r]
  set outFileID [open $DB_OUTFILE.tmp w]
  # Use i to keep track of how many lines we loaded into the database for DEBUG.
  set i 0
  # Load the entire file into memory (read $inFileID), then create a list
  # delimited by \n. Finally loop through each 'line', prepend the sensorID (sid)
  # to it, and append the new line to the tmp file.
  foreach line [split [read $inFileID] \n] {
    if {$line != ""} {puts $outFileID "$sensorID|$line"; incr i}
  }
  close $inFileID
  close $outFileID
  file delete $DB_OUTFILE
                                                                                                                                   
  InfoMessage "Loading $i cnxs from $fileName into $tableName."
  if {$DBPASS != "" } {
    set cmd "mysql --local-infile -D $DBNAME -h $DBHOST -P $DBPORT -u $DBUSER --password=$DBPASS\
     -e \"LOAD DATA LOCAL INFILE '$DB_OUTFILE.tmp' INTO TABLE $tableName FIELDS TERMINATED\
     BY '|'\""
  } else {
    set cmd "mysql --local-infile -D $DBNAME -h $DBHOST -P $DBPORT -u $DBUSER\
     -e \"LOAD DATA LOCAL INFILE '$DB_OUTFILE.tmp' INTO TABLE $tableName FIELDS TERMINATED\
     BY '|'\""
  }
  # The loader child proc does the LOAD for us.
  puts $loaderWritePipe [list $DB_OUTFILE.tmp $cmd]
  flush $loaderWritePipe
}

proc RcvPortscanFile { socketID fileName } {
  global TMPDATADIR DBHOST DBPORT DBNAME DBUSER DBPASS loaderWritePipe
  InfoMessage "Recieving portscan file $fileName."
  fconfigure $socketID -translation binary
  set PS_OUTFILE $TMPDATADIR/$fileName
  set fileID [open $PS_OUTFILE w]
  fcopy $socketID $fileID
  close $fileID
  close $socketID
  InfoMessage "Loading $fileName into DB."
  if {$DBPASS != "" } {
    set cmd "mysql --local-infile -D $DBNAME -h $DBHOST -P $DBPORT -u $DBUSER --password=$DBPASS\
     -e \"LOAD DATA LOCAL INFILE '$PS_OUTFILE' INTO TABLE portscan FIELDS TERMINATED\
     BY '|'\""
  } else {
    set cmd "mysql --local-infile -D $DBNAME -h $DBHOST -P $DBPORT -u $DBUSER\
     -e \"LOAD DATA LOCAL INFILE '$PS_OUTFILE' INTO TABLE portscan FIELDS TERMINATED\
     BY '|'\""
  }
  # The loader child proc does the LOAD for us.
  puts $loaderWritePipe [list $PS_OUTFILE $cmd]
  flush $loaderWritePipe
}

proc DiskReport { socketID fileSystem percentage } {
  global agentSensorName
  SendSystemInfoMsg $agentSensorName($socketID) "$fileSystem $percentage"
}






