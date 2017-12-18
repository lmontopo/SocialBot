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

parseEvents = (results) ->
  if !results
    return "There are no upcoming social events."
  parsedResults = ["Upcoming Social Events:"]
  for event, details of results
    eventString = "#{event} at #{details.location} on #{details.date}."
    parsedResults.push eventString
  return parsedResults.join('\n')

listEvents = (res) ->
  results = res.robot.brain.get('events')
  res.send parseEvents(results)

addEvent = (res) -> 
  eventName = res.match[1].trim()
  eventDate = res.match[2].trim()
  eventLocation = res.match[3].trim()
  currentEvents = res.robot.brain.get('events') || {}

  if eventName in currentEvents
    res.send "An event with the name #{eventName} already exists."
    return

  event = {
    'location': eventLocation,
    'date': eventDate,
    'atendees': []
  }

  currentEvents[eventName] = event
  res.robot.brain.set('events', currentEvents)
  res.send "#{eventName} was added."

joinEvent = (res) ->
  eventName = res.match[1].trim()
  user = res.message.user.name
  events = res.robot.brain.get('events')

  if !events[eventName]
    res.send "An event with the name #{eventName} does not exist."
    return

  if user in events[eventName].atendees
    res.send "You are already atending #{eventName}."
    return

  events[eventName].atendees.push(user)
  # Hubot might save automaitcally on intervals of 5 (seconds? milliseconds?)
  # res.robot.brain.emit 'save'

  res.send "You are now atending #{eventName}."


module.exports = (robot) ->

  robot.respond /list/i, listEvents
  robot.respond /organize ([\w ]+) for ([\w ]+) at ([\w ]+)$/i, addEvent
  robot.respond /I'm in ([\w ]+)$/i, joinEvent