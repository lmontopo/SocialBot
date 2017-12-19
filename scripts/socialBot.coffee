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
#   SocialBot organize <event-name> for <date> at <place> - Adds event to events list and starts an RSVP
#   SocialBot I'm in for <event> - RSVPs you as coming to <event>
#   SocialBot abandon <event> - Remove yourself from <event>
#   SocialBot cancel <event> - removes <event> from upcoming events list
#

chrono = require('chrono-node')

NO_SUCH_EVENT = (eventName) -> "An event with the name #{eventName} does not exist."
ALREADY_EXISTS = (eventName) -> "An event with the name #{eventName} already exists."
NO_EVENTS = () -> "There are no upcoming social events."
EVENT_DETAILS = (selectedEvent, details) -> "#{selectedEvent} at #{details.location} on #{details.date} at #{details.time}."
ADDED_BY = (eventName, user) -> "#{eventName} was added by @#{user}."
ALREADY_ATTENDING = (user, eventName) -> "@#{user} You are already atending #{eventName}."
NOW_ATTENDING = (user, eventName) -> "@#{user} You are now atending #{eventName}."
NEVER_ATTENDING = (user, eventName) -> "@#{user} You were not planning to attend #{eventName}."
NO_LONGER_ATTENDING = (user, eventName) -> "@#{user} You are no longer attending #{eventName}."
CANCEL_FORBIDDEN = (user, creators, eventName) -> "@#{user} Only #{creators} can cancel #{eventName}."
CANCELLED = (user, eventName) -> "@#{user} You have cancelled #{eventName}."
BAD_TIME = (user, eventName) -> "@#{user} You have entered an invalid time for #{eventName}"

getEvent = (eventName, brain) ->
  events = getEvents(brain)
  return events[eventName]

getEvents = (brain) ->
  events = brain.get('events')
  if !events
    brain.set('events', {})

  return brain.get('events')

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

parseCreators = (event) ->
  return event.creators.join(', ')

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
  user = res.message.user.name

  if eventName of currentEvents
    res.send ALREADY_EXISTS(eventName)
    return

  if !eventDate
    res.send BAD_TIME(user, eventName)
    return

  newEvent = {
    'location': eventLocation,
    'date': eventDate.toDateString(),
    'time': eventDate.toLocaleTimeString(),
    'attendees': [user],
    'creators': [user]
  }

  currentEvents[eventName] = newEvent
  res.robot.brain.set('events', currentEvents)
  res.send ADDED_BY(eventName, user)

joinEvent = (res) ->
  eventName = res.match[1].trim()
  user = res.message.user.name
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(eventName)
    return

  if user in selectedEvent.attendees
    res.send ALREADY_ATTENDING(user, eventName)
    return

  selectedEvent.attendees.push(user)
  res.send NOW_ATTENDING(eventName)

abandonEvent = (res) ->
  eventName = res.match[1].trim()
  user = res.message.user.name
  selectedEvent = getEvent(eventName, res.robot.brain)

  if !selectedEvent
    res.send NO_SUCH_EVENT(user, eventName)
    return

  if user not in selectedEvent.attendees
    res.send NEVER_ATTENDING(user, eventName)
    return

  users = (u for u in selectedEvent.attendees when u isnt user)
  selectedEvent.attendees = users

  res.send NO_LONGER_ATTENDING(user, eventName)

cancelEvent = (res) ->
  eventName = res.match[1].trim()
  user = res.message.user.name
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
  res.send CANCELLED(user, eventName)

test = (res) ->
  getEvents(res.robot.brain)

module.exports = (robot) ->

  robot.respond /list/i, listEvents
  robot.respond /organize ([\w ]+) for ([\w: ]+) at ([\w ]+)$/i, addEvent
  robot.respond /I'm in ([\w ]+)$/i, joinEvent
  robot.respond /abandon ([\w ]+)$/i, abandonEvent
  robot.respond /who's in ([\w ]+)$/i, listUsers
  robot.respond /cancel ([\w ]+)$/i, cancelEvent
  robot.respond /test$/i, test
