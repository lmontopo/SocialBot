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
#   SocialBot list - lists all upcoming social events.
#   SocialBot who's in <event> - lists people who have RSVPed to <event>
#   SocialBot organize <event-name> for <date-time> at <place> - Adds event to events list and starts an RSVP
#   SocialBot I'm in for <event> - RSVPs you as coming to <event>
#   SocialBot abandon <event> - Remove yourself from <event>
#   SocialBot cancel <event> - removes <event> from upcoming events list
#   SocialBot (change|set) RSVP deadline for <event> to <date-time> - Set an RSVP deadline for <event> to be <date-time>. The default deadline is a week before <event> starts.
#   SocialBot add description to <event-name>: <description> - Add a description to an event
#   SocialBot get details <event-name> - See event name, date, time and description

chrono = require 'chrono-node'
schedule = require 'node-schedule'
ical = require 'ical-generator'
link = require 'generate-download-link'
FormData = require 'form-data'

NO_SUCH_EVENT = (eventName) -> "An event with the name #{eventName} does not exist."
ALREADY_EXISTS = (eventName) -> "An event with the name #{eventName} already exists."
NO_EVENTS = () -> "There are no upcoming social events."
EVENT_DETAILS = (selectedEvent, details) -> "#{selectedEvent} at #{details.location} on #{getDateReadable details.date}."
EVENT_DESCRIPTION = (user, selectedEvent, details) ->"@#{user} #{EVENT_DETAILS(selectedEvent, details)}\n\t#{details.description}"
ADDED_BY = (eventName, user) -> "#{eventName} was added by @#{user}."
ALREADY_ATTENDING = (user, eventName) -> "@#{user} You are already atending #{eventName}."
NOW_ATTENDING = (user, eventName) -> "@#{user} You are now atending #{eventName}."
NEVER_ATTENDING = (user, eventName) -> "@#{user} You were not planning to attend #{eventName}."
NO_LONGER_ATTENDING = (user, eventName) -> "@#{user} You are no longer attending #{eventName}."
CANCEL_FORBIDDEN = (user, creators, eventName) -> "@#{user} Only #{creators} can cancel #{eventName}."
CANCELLED = (creator, users, eventName) -> "Event #{eventName} has been cancelled by #{creator}.\n#{users}"
BAD_TIME = (user, eventName) -> "@#{user} You have entered an invalid time for #{eventName}."
EVENT_REMINDER = (users, eventName) -> "REMINDER: Event #{eventName} is tomorrow!\n#{users}"
DEADLINE_PASSED = (user, eventName) -> "@#{user} the deadline to join #{eventName} has passed."
RSVP_REMINDER = (eventName, date) -> "@all Deadline to RSVP for #{eventName} is #{date}!"
CREATOR_ADDED = (user, eventName) -> "@#{user} is now a creator of #{eventName}."
NEW_DEADLINE = (eventName, deadline) -> "The deadline to RSVP for #{eventName} is now #{getDateReadable deadline}."
CHANGE_DEADLINE_FORBIDDEN = (user, creators, eventName) -> "@#{user} Only #{creators} can change the deadline to RSVP for #{eventName}."
NOTIFY_ATTENDEES = (user, users, eventName, message) -> "Message from #{user} regarding #{eventName}:\n#{message}\n#{users}"
ONLY_ATTENDEES_CAN_NOTIFY = () -> "Only attendees can send a notification about this event."
CANNOT_ABANDON = (user, eventName) -> "@#{user} You cannot abandon #{eventName} before selecting a replacement creator."
ADD_DESCRIPTION_FORBIDDEN = (user, creators, eventName) -> "@#{user} Only #{creators} can edit the description of #{eventName}."
POLL_CREATED = (eventName, poll) -> "@all A poll for #{eventName} has started. Tag socialbot with one of the following commands to vote:\n#{parseOptions(poll)}"
POLL_CLOSED = (eventName, winner) -> "Poll for #{eventName} has closed. The winner is #{winner}!"
NO_SUCH_POLL = (user, eventName) -> "@#{user} No poll exists for #{eventName}"
NO_SUCH_OPTION = (user, option, eventName) -> "@#{user} No option '#{option}' in poll #{eventName}"
YOU_ALREADY_VOTED = (user, eventName) -> "@#{user} You've already voted in the poll for #{eventName}"
VOTE_SUCCESSFUL = (user, option, eventName) -> "@#{user} You've voted for #{option} in the poll for #{eventName}"
NO_ONE_VOTED = (eventName, creators) -> "#{creators} No one voted in the poll for #{eventName}"


#
# Helper Methods
#
getEvent = (eventName, brain) ->
  events = getEvents(brain)
  return events[eventName]

getPoll = (eventName, brain) ->
  polls = getPolls(brain)
  return polls[eventName]

getPolls = (brain) ->
  polls = brain.get('polls')
  if !polls
    brain.set('polls', {})

  return brain.get('polls')

getEvents = (brain) ->
  events = brain.get('events')
  if !events
    brain.set('events', {})

  return brain.get('events')

createEvent = (res, eventName, eventLocation, eventDate = undefined) ->
  currentEvents = getEvents(res.robot.brain)
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
  polls = getPolls(res.robot.brain)

  if eventName of polls
    return false

  newPoll = {
    options: {},
    eventName: eventName,
    voted: []
  }

  for dateOption in eventDateOptions
    newPoll.options[dateOption] = 0

  polls[eventName] = newPoll
  setPollDeadline(res, newPoll)
  res.send POLL_CREATED(eventName, newPoll)
  return true


getDate = (dateString) ->
  return new Date(dateString)

getDateReadable = (dateString) ->
  date = getDate(dateString)
  return date.toDateString() + ' at ' + date.toLocaleTimeString()

getUsername = (res) ->
  return res.message.user.name

parseEvents = (results) ->
  if !results
    return NO_EVENTS()
  parsedResults = ["Upcoming Social Events:"]
  for selectedEvent, details of results
    eventString = EVENT_DETAILS(selectedEvent, details)
    parsedResults.push eventString
  return parsedResults.join('\n')

listEvents = (res) ->
  events = getEvents(res.robot.brain)
  res.send parseEvents(events)

parseUsers = (event) ->
  return event.attendees.join(', ')

parseNotifyUsers = (event) ->
  users = ('@' + user for user in event.attendees)
  return users.join(', ')

parseCreators = (event) ->
  return event.creators.join(', ')

parseNotifyCreators = (event) ->
  creators = ('@' + creator for creator in event.creators)
  return creators.join(', ')

parseOptions = (poll) ->
  options = ('vote ' + option + ' for ' + poll.eventName for option, val of poll.options)
  return options.join('\n')

#
# Job Scheduling
#
cancelScheduledJob = (jobName) ->
  job = schedule.scheduledJobs[jobName]
  if job
    job.cancel()

eventReminder = (res, selectedEvent) ->
  date = getDate(selectedEvent.date)
  date.setDate(date.getDate() - 1)
  jobName = "#{selectedEvent.name}_REMIND"

  cancelScheduledJob(jobName)
  schedule.scheduleJob jobName, date, () -> res.send(EVENT_REMINDER(parseNotifyUsers(selectedEvent), selectedEvent.name))

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

# TO-DO deal with ties
closePoll = (res, poll) ->
  selectedEvent = getEvent(poll.eventName, res.robot.brain)

  if !poll.voted.length
    res.send NO_ONE_VOTED(selectedEvent.name, parseNotifyCreators(selectedEvent))

  else
    winner = decideWinner(poll)
    winner = chrono.parseDate(winner)

    selectedEvent.date = winner

    res.send POLL_CLOSED(selectedEvent.name, getDateReadable(winner))

  delete getPolls(res.robot.brain)[poll.eventName]

decideWinner = (poll) ->
  winner = null
  winningValue = 0

  for option, val of poll.options
    if val > winningValue
      winningValue = val
      winner = option

  return winner

#
# User Command Handlers
#
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
  currentEvents = getEvents(res.robot.brain)
  user = getUsername(res)

  if !eventDate
    res.send BAD_TIME(user, eventName)
    return

  if createEvent(res, eventName, eventLocation, eventDate)
    res.send ADDED_BY(eventName, user)

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
  currentDate = new Date()
  rsvpCloseDate = getDate(selectedEvent.rsvpCloseDate)

  if rsvpCloseDate < currentDate
    res.send DEADLINE_PASSED(user, eventName)
    return

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
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
  events = getEvents(res.robot.brain)
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send CANCEL_FORBIDDEN(user, creators, eventName)
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
  events = getEvents(res.robot.brain)
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user not in selectedEvent.creators
    creators = parseCreators(selectedEvent)
    res.send CANCEL_FORBIDDEN(user, creators, eventName)
    return

  delete events[eventName]
  res.send CANCELLED(user, parseNotifyUsers(selectedEvent), eventName)

forceRemind = (res) ->
  eventName = res.match[1].trim()
  selectedEvent = getEvent(eventName, res.robot.brain)
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
    res.send CHANGE_DEADLINE_FORBIDDEN(user, creators, eventName)
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

  res.send NOTIFY_ATTENDEES(user, parseNotifyUsers(selectedEvent), eventName, message)

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
    res.send ADD_DESCRIPTION_FORBIDDEN(user, creators, eventName)
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

vote = (res) ->
  option = res.match[1].trim()
  eventName = res.match[2].trim()
  user = getUsername(res)
  poll = getPoll(eventName, res.robot.brain)
  # TO-DO: ADD ERROR MESSAGES

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


test = (res) ->

  cal = ical({
    prodId: {company: 'superman-industries.com', product: 'ical-generator'},
    name: 'My Testfeed',
    timezone: 'Europe/Berlin'
  });

  https = require('https')

  form = new FormData();

  form.append('room', process.env.HUBOT_LCB_ROOMS);
  form.append('post', 'true');
  form.append('file', cal.toString());

  headers = form.getHeaders()
  headers.Authorization = 'Bearer ' + process.env.HUBOT_LCB_TOKEN

  request = https.request({
    method: 'post',
    host: process.env.HUBOT_LCB_HOSTNAME,
    port: process.env.HUBOT_LCB_PORT,
    path: '/files',
    headers: headers
  })

  form.pipe(request)

  request.on('response', (res) -> console.log(res.statusCode))

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
  robot.respond /test$/i, test
  robot.respond /remind about ([\w ]+$)/i, forceRemind
  robot.respond /tell ([\w ]+) attendees \"(.+)\"$/i, notifyAllAttendees
  robot.respond /add creator ([\w ]+) to ([\w ]+)/i, addCreator
  robot.respond /add description to ([\w ]+): (.+)$/i, addDescription
  robot.respond /get details ([\w ]+)$/i, getEventDetails
