# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.
#
#   These are from the scripting documentation: https://github.com/github/hubot/blob/master/docs/scripting.md
#
#Commands:
#   SocialBot list - List all upcoming social events.
#   SocialBot who's in <event-name> - List people who have RSVPed as going to <event>.
#   SocialBot organize <event-name> for <date-time> at <place> - Add event to events list and start accepting RSVPs.
#   SocialBot organize <event-name> with poll at <event-place> for <comma-separated-choices-of-date-time> - Add event to events list and creates a poll for the event time with choices mentioned.  Poll lasts 24 hours.
#   SocialBot I'm in for <event-name> - Add yourself to attendees for <event-name>.
#   SocialBot abandon <event-name> - Remove yourself from <event-name>.
#   SocialBot cancel <event-name> - Remove <event-name> from upcoming events list.
#   SocialBot (change|set) RSVP deadline for <event-name> to <date-time> - Set an RSVP deadline for <event-name> to be <date-time>. The default deadline is a week before <event> starts.
#   SocialBot add description to <event-name>: <description> - Add a description to an event.
#   SocialBot get details <event-name> - See event name, date, time and description.
#   SocialBot change <event-name> time to <date-time> - Update the <date-time> of <event-name>.
#   SocialBot vote <choice> for <event-name> - Vote for date <choice> in the poll for <event-name>.
#   SocialBot remind about <event-name> - Remind people to RSVP for <event-name> before deadline.
#   SocialBot add creator <username> to <event-name> - Add a user as an organizer of an event.
#   SocialBot tell <event-name> attendees <message> - Ping all attendees of <event-name> with custom message.

chrono = require 'chrono-node'
schedule = require 'node-schedule'

NO_SUCH_EVENT = (eventName) -> "An event with the name #{eventName} does not exist."
ALREADY_EXISTS = (eventName) -> "An event with the name #{eventName} already exists."
NO_EVENTS = () -> "There are no upcoming social events."
EVENT_DETAILS = (selectedEvent, details) -> "#{selectedEvent} at #{details.location} on #{getDateReadable details.date}."
EVENT_DESCRIPTION = (user, selectedEvent, details) ->"@#{user} #{EVENT_DETAILS(selectedEvent, details)}\n\t#{details.description || "No description"} "
ADDED_BY = (eventName, user) -> "#{eventName} was added by @#{user}."
ALREADY_ATTENDING = (user, eventName) -> "@#{user} You are already attending #{eventName}."
NOW_ATTENDING = (user, eventName) -> "@#{user} You are now attending #{eventName}."
NEVER_ATTENDING = (user, eventName) -> "@#{user} You were not planning to attend #{eventName}."
NO_LONGER_ATTENDING = (user, eventName) -> "@#{user} You are no longer attending #{eventName}."
CANCELLED = (creator, users, eventName) -> "Event #{eventName} has been canceled by #{creator}.\n#{users}"
BAD_TIME = (user, eventName) -> "@#{user} You have entered an invalid time for #{eventName}."
EVENT_REMINDER = (users, eventName) -> "REMINDER: Event #{eventName} is tomorrow!\n#{users}"
DEADLINE_PASSED = (user, eventName) -> "@#{user} the deadline to join #{eventName} has passed."
RSVP_REMINDER = (eventName, date) -> "@all Deadline to RSVP for #{eventName} is #{date}!"
CREATOR_ADDED = (user, eventName) -> "@#{user} is now a creator of #{eventName}."
NEW_DEADLINE = (eventName, deadline) -> "The deadline to RSVP for #{eventName} is now #{getDateReadable deadline}."
NOTIFY_ATTENDEES = (user, users, eventName, message) -> "Message from #{user} regarding #{eventName}:\n#{message}\n#{users}"
ONLY_ATTENDEES_CAN_NOTIFY = () -> "Only attendees can send a notification about this event."
CANNOT_ABANDON = (user, eventName) -> "@#{user} You cannot abandon #{eventName} before selecting a replacement creator."
POLL_CREATED = (eventName, poll) -> "@all A poll for #{eventName} has started. Tag socialbot with one of the following commands to vote:\n#{parseOptions(poll)}"
POLL_CLOSED = (eventName, winner) -> "Poll for #{eventName} has closed. The winner is #{winner}!"
NO_SUCH_POLL = (user, eventName) -> "@#{user} No poll exists for #{eventName}"
NO_SUCH_OPTION = (user, option, eventName) -> "@#{user} No option '#{option}' in poll #{eventName}"
YOU_ALREADY_VOTED = (user, eventName) -> "@#{user} You've already voted in the poll for #{eventName}"
VOTE_SUCCESSFUL = (user, option, eventName) -> "@#{user} You've voted for #{option} in the poll for #{eventName}"
NO_ONE_VOTED = (eventName, creators) -> "#{creators} No one voted in the poll for #{eventName}"
TIME_CHANGE_DURING_POLL_FORBIDDEN = (user, eventName) -> "@#{user} Wait for poll to end before changing the time for #{eventName}."
NOT_CREATOR = (user, creators, eventName) -> "@#{user} Only #{creators} can modify #{eventName}."
CREATOR_BREAK_TIE = (eventName, creators, winners) -> "#{creators} The poll for #{eventName} resulted in a tie. Tag socialbot with one of the winners:\n#{winners}"
EVENT_FOLLOW_UP = (eventName, creators) -> "#{creators} Who showed up for the <event-name> yesterday?"
SHAME = (eventName, users) -> "SHAME.  You all said you'd show up to #{eventName} and you didn't!\n#{users}"

#
# Helper Methods
#
getEvent = (eventName, brain) ->
  console.log(eventName)
  events = getFromRedis(brain, 'events')
  return events[eventName]

getPoll = (eventName, brain) ->
  polls = getFromRedis(brain, 'polls')
  return polls[eventName]

getFromRedis = (brain, key) ->
  items = brain.get(key)
  if !items
    brain.set(key, {})

  return brain.get(key)

createEvent = (res, eventName, eventLocation, eventDate = undefined) ->
  currentEvents = getFromRedis(res.robot.brain, 'events')
  user = getUsername(res)

  if eventName of currentEvents
    res.send ALREADY_EXISTS(eventName)
    return false

  rsvpCloseDate = undefined

  if eventDate
    rsvpCloseDate = new Date()
    rsvpCloseDate.setDate(eventDate.getDate() - 7)

  newEvent = {
    'name': eventName,
    'description': '',
    'location': eventLocation,
    'date': eventDate,
    'attendees': [user],
    'creators': [user],
    'rsvpCloseDate': rsvpCloseDate
  }

  currentEvents[eventName] = newEvent

  if eventDate
    eventReminder(res, newEvent)
    setRsvpReminder(res, newEvent)

  return true

createPoll = (res, eventName, eventDateOptions) ->
  polls = getFromRedis(res.robot.brain, 'polls')

  if eventName of polls
    return false

  newPoll = {
    options: {},
    eventName: eventName,
    voted: []
  }

  for dateOption in eventDateOptions
    newPoll.options[dateOption.trim()] = 0

  polls[eventName] = newPoll
  setPollDeadline(res, newPoll)
  res.send POLL_CREATED(eventName, newPoll)
  return true

getDate = (dateString) ->
  return new Date(dateString)

getDateReadable = (dateString) ->
  if dateString is undefined
    return 'Undecided date and time'

  date = getDate(dateString)
  return date.toDateString() + ' at ' + date.toLocaleTimeString()

getUsername = (res) ->
  return res.message.user.name

parseEvents = (results) ->
  if results.length == 0
    return NO_EVENTS()
  parsedResults = ["Upcoming Social Events:"]
  for selectedEvent, details of results
    eventString = EVENT_DETAILS(selectedEvent, details)
    parsedResults.push eventString
  return parsedResults.join('\n')

parseUsers = (event) ->
  return event.attendees.join(', ')

parseNotify = (users) ->
  users = ('@' + user for user in users)
  return users.join(', ')

parseCreators = (event) ->
  return event.creators.join(', ')

parseOptions = (poll) ->
  options = ('vote ' + option + ' for ' + poll.eventName for option, val of poll.options)
  return options.join('\n')

parseWinningDates = (eventName, winners) ->
  options = ('change ' + eventName + ' time to ' + getDateReadable(winner) for winner in winners)
  return options.join('\n')

decideWinner = (poll) ->
  winners = []
  winningValue = 0

  for option, val of poll.options
    if val == winningValue
      winners.push(option)
    else if val > winningValue
      winningValue = val
      winners = [option]

  return winners


#
# Job Scheduling
#
cancelScheduledJob = (jobName) ->
  job = schedule.scheduledJobs[jobName]
  if job
    job.cancel()

cancelAllScheduledJobs = (eventName) ->
  jobNames = [
    "#{eventName}_REMIND"
    "#{eventName}_RSVP"
    "#{eventName}_POLL_CLOSE"
  ]

  cancelScheduledJob(jobName) for jobName in jobNames

eventReminder = (res, selectedEvent) ->
  date = getDate(selectedEvent.date)
  date.setDate(date.getDate() - 1)
  jobName = "#{selectedEvent.name}_REMIND"

  cancelScheduledJob(jobName)
  schedule.scheduleJob jobName, date, () -> res.send(EVENT_REMINDER(parseNotify(selectedEvent.attendees), selectedEvent.name))

setRsvpReminder = (res, selectedEvent) ->
  date = getDate(selectedEvent.rsvpCloseDate)
  date.setDate(date.getDate() - 1)
  jobName = "#{selectedEvent.name}_RSVP"

  cancelScheduledJob(jobName)
  schedule.scheduleJob jobName, date, () -> res.send(RSVP_REMINDER(selectedEvent.name, getDateReadable(date)))

setPollDeadline = (res, poll) ->
  date = new Date()
  date.setDate(date.getDate() + 1)
  jobName = "#{poll.eventName})_POLL_CLOSE"

  cancelScheduledJob(jobName)
  schedule.scheduleJob jobName, date, () -> closePoll(res, poll)

closePoll = (res, poll) ->
  selectedEvent = getEvent(poll.eventName, res.robot.brain)
  eventName = selectedEvent.name
  creators = parseNotify(selectedEvent.creators)

  if !poll.voted.length
    res.send NO_ONE_VOTED(eventName, creators)

  else
    winners = decideWinner(poll)
    winners = (chrono.parseDate(winner) for winner in winners)

    if winners.length == 1
      selectedEvent.date = winner
      res.send POLL_CLOSED(eventName, getDateReadable(winner))
      eventReminder(res, eventName)
      setRsvpReminder(res, eventName)

    else
      res.send CREATOR_BREAK_TIE(eventName, creators, parseWinningDates(eventName, winners))

  delete getFromRedis(res.robot.brain, 'polls')[eventName]

eventFollowup = (res, eventName) ->
  # create a job to follow up with creator the day after an event to ask who showed
  selectedEvent = getEvent(eventName, res.robot.brain)
  creators = parseNotify(selectedEvent.creators)
  date = getDate(selectedEvent.date)
  date.setDate(date.getDate() + 1)

  jobName = "#{eventName.eventName})_WHO_ATTENDED"

  cancelScheduledJob(jobName)

  schedule.scheduleJob jobName, date, () -> res.send(EVENT_FOLLOW_UP(eventName, creators))



#
# User Command Handlers
#
listEvents = (res) ->
  allEventNames = Object.keys(getFromRedis(res.robot.brain, 'events'))
  if allEventNames.length == 0
    res.send NO_EVENTS()
    return

  currentEvents = []
  startOfToday = new Date()
  startOfToday.setHours(0,0,0,0)
  for e in allEventNames
    eventObj = getEvent(e, res.robot.brain)
    if getDate(eventObj.date) > startOfToday
      currentEvents.push(eventObj)

  res.send parseEvents(currentEvents)

listUsers = (res) ->
  eventName = res.match[1].trim()
  selectedEvent = getEvent(eventName, res.robot.brain)
  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return
  res.send parseUsers(selectedEvent)

addEvent = (res) ->
  eventName = res.match[1].trim()
  eventDate = chrono.parseDate(res.match[2].trim())
  eventLocation = res.match[3].trim()
  currentEvents = getFromRedis(res.robot.brain, 'events')
  user = getUsername(res)

  if !eventDate
    res.send BAD_TIME(user, eventName)
    return

  if createEvent(res, eventName, eventLocation, eventDate)
    res.send ADDED_BY(eventName, user)

  eventFollowup(res, eventName)

  return

addEventWithPoll = (res) ->
  eventName = res.match[1].trim()
  eventLocation = res.match[2].trim()
  eventDateOptions = res.match[3].trim().split(',')

  if not createEvent(res, eventName, eventLocation)
    return

  poll = createPoll(res, eventName, eventDateOptions)

  if !poll
    return

joinEvent = (res) ->
  eventName = res.match[1].trim()
  user = getUsername(res)
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  currentDate = new Date()
  rsvpCloseDate = getDate(selectedEvent.rsvpCloseDate)

  if rsvpCloseDate < currentDate
    res.send DEADLINE_PASSED(user, eventName)
    return

  if user in selectedEvent.attendees
    res.send ALREADY_ATTENDING(user, eventName)
    return

  selectedEvent.attendees.push(user)
  res.send NOW_ATTENDING(eventName)

addCreator = (res) ->
  newCreator = res.match[1].trim()
  eventName = res.match[2].trim()
  user = getUsername(res)
  events = getFromRedis(res.robot.brain, 'events')
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send NOT_CREATOR(user, creators, eventName)
    return

  if newCreator not in selectedEvent.attendees
    selectedEvent.attendees.push(newCreator)

  selectedEvent.creators.push(newCreator)
  res.send CREATOR_ADDED(newCreator, eventName)

abandonEvent = (res) ->
  eventName = res.match[1].trim()
  user = getUsername(res)
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(user, eventName)
    return

  if user not in selectedEvent.attendees
    res.send NEVER_ATTENDING(user, eventName)
    return

  if user in selectedEvent.creators

    if selectedEvent.creators.length == 1
      res.send CANNOT_ABANDON(user, eventName)
      return

    creators = (c for c in selectedEvent.creators when c isnt user)
    selectedEvent.creators = creators

  users = (u for u in selectedEvent.attendees when u isnt user)
  selectedEvent.attendees = users

  res.send NO_LONGER_ATTENDING(user, eventName)

cancelEvent = (res) ->
  eventName = res.match[1].trim()
  user = getUsername(res)
  events = getFromRedis(res.robot.brain, 'events')
  selectedEvent = getEvent(eventName, res.robot.brain)
  poll = getPoll(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send NOT_CREATOR(user, creators, eventName)
    return

  if poll
    delete getFromRedis(res.robot.brain, 'polls')[eventName]

  cancelAllScheduledJobs(eventName)

  delete events[eventName]
  res.send CANCELLED(user, parseNotify(selectedEvent.attendees), eventName)

forceRemind = (res) ->
  eventName = res.match[1].trim()
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  date = getDateReadable(selectedEvent.rsvpCloseDate)
  res.send RSVP_REMINDER(eventName, date)
  return

editRSVP = (res) ->
  eventName = res.match[2].trim()
  user = getUsername(res)
  newDeadline = chrono.parseDate(res.match[3].trim())
  selectedEvent = getEvent(eventName, res.robot.brain)

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send NOT_CREATOR(user, creators, eventName)
    return

  if !newDeadline
    res.send BAD_TIME(user, eventName)
    return

  selectedEvent.rsvpCloseDate = newDeadline
  setRsvpReminder(res, selectedEvent)
  res.send NEW_DEADLINE(eventName, newDeadline)

notifyAllAttendees = (res) ->
  eventName = res.match[1].trim()
  message = res.match[2].trim()
  user = res.message.user.name
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user not in selectedEvent.attendees
    res.send ONLY_ATTENDEES_CAN_NOTIFY()
    return

  res.send NOTIFY_ATTENDEES(user, parseNotify(selectedEvent.attendees), eventName, message)

addDescription = (res) ->
  eventName = res.match[1].trim()
  description = res.match[2].trim()
  user = getUsername(res)
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send NOT_CREATOR(user, creators, eventName)
    return

  selectedEvent.description = description
  res.send EVENT_DESCRIPTION(user, eventName, selectedEvent)

getEventDetails = (res) ->
  eventName = res.match[1].trim()
  user = getUsername(res)
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  res.send EVENT_DESCRIPTION(user, eventName, selectedEvent)

editEventTime = (res) ->
  eventName = res.match[1].trim()
  eventDate = chrono.parseDate(res.match[2].trim())
  selectedEvent = getEvent(eventName, res.robot.brain)
  poll = getPoll(eventName, res.robot.brain)
  user = getUsername(res)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if !eventDate
    res.send BAD_TIME(user, eventName)
    return

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send NOT_CREATOR(user, creators, eventName)
    return

  if poll
    res.send TIME_CHANGE_DURING_POLL_FORBIDDEN(user, eventName)
    return

  selectedEvent.date = eventDate
  eventReminder(res, eventName)
  setRsvpReminder(res, eventName)

  res.send EVENT_DESCRIPTION(user, eventName, selectedEvent)

vote = (res) ->
  option = res.match[1].trim()
  eventName = res.match[2].trim()
  user = getUsername(res)
  poll = getPoll(eventName, res.robot.brain)

  if !poll
    res.send NO_SUCH_POLL(user, eventName)
    return

  if option not of poll.options
    res.send NO_SUCH_OPTION(user, option, eventName)
    return

  if user in poll.voted
    res.send YOU_ALREADY_VOTED(user, eventName)
    return

  poll.options[option] += 1
  poll.voted.push(user)
  res.send VOTE_SUCCESSFUL(user, option, eventName)

eventAttendance = (res) ->
  user = getUsername(res)

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send NOT_CREATOR(user, creators, eventName)
    return

  eventName = res.match[1].trim()
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  actualAttendees = res.match[2].trim().split(',')
  eventAttendees = selectedEvent.attendees
  bailers = (user for user in eventAttendees if user not in actualAttendees)

  res.send SHAME(eventName, parseNotify(bailers))


test = (res) ->
  parseOptions({
    eventName: 'Kelly',
    options: {
      'today': 0,
      'tmr': 0
    }
  })


module.exports = (robot) ->

  robot.respond /list/i, listEvents
  robot.respond /vote ([\w: ]+) for ([\w ]+)$/i, vote
  robot.respond /organize ([\w ]+) with poll at ([\w ]+) for: ([\w:, ]+)$/i, addEventWithPoll
  robot.respond /organize ([\w ]+) for ([\w: ]+) at ([\w ]+)$/i, addEvent
  robot.respond /I'm in ([\w ]+)$/i, joinEvent
  robot.respond /abandon ([\w ]+)$/i, abandonEvent
  robot.respond /who's in ([\w ]+)$/i, listUsers
  robot.respond /cancel ([\w ]+)$/i, cancelEvent
  robot.respond /(change|set) RSVP deadline for ([\w ]+) to ([\w: ]+)$/i, editRSVP
  robot.respond /remind about ([\w ]+$)/i, forceRemind
  robot.respond /tell ([\w ]+) attendees \"(.+)\"$/i, notifyAllAttendees
  robot.respond /add creator ([\w ]+) to ([\w ]+)/i, addCreator
  robot.respond /add description to ([\w ]+): (.+)$/i, addDescription
  robot.respond /get details ([\w ]+)$/i, getEventDetails
  robot.respond /change ([\w ]+) time to ([\w: ]+)$/i, editEventTime
  robot.respond /The following people showed up to ([\w ]+): ([\w, ]+)$/i, eventAttendance

  # Test
  robot.respond /test$/i, test
