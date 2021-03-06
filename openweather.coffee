module.exports = (env) ->

  Promise = env.require 'bluebird'
  convict = env.require "convict"
  assert = env.require 'cassert'

  weatherLib = require "openweathermap"
  Promise.promisifyAll(weatherLib)
  PromiseRetryer = require('promise-retryer')(Promise)

  class OpenWeather extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("OpenWeatherDevice", {
        configDef: deviceConfigDef.OpenWeatherDevice,
        createCallback: (config) => new OpenWeatherDevice(config)
      })
      @framework.deviceManager.registerDeviceClass("OpenWeatherForecastDevice", {
        configDef: deviceConfigDef.OpenWeatherForecastDevice,
        createCallback: (config) => new OpenWeatherForecastDevice(config)
      })

  handleError = (result) ->
    code = parseInt(result.cod, 10)
    if code isnt 200
      if result.message?.length > 0
        throw new Error("#{result.message} (#{code})")
      else
        if code is 404
          throw new Error("Location not found")
        else
          throw new Error("Error code: #{code}")
    return


  class OpenWeatherDevice extends env.devices.Device
    attributes:
      status:
        description: "The actual status"
        type: "string"
      temperature:
        description: "The measured temperature"
        type: "number"
        unit: '°C'
        acronym: 'T'
      humidity:
        description: "The actual degree of Humidity"
        type: "number"
        unit: '%'
        acronym: 'RH'
      pressure:
        description: "The expected pressure"
        type: "number"
        unit: 'mbar'
        acronym: 'P'
      windspeed:
        description: "The wind speed"
        type: "number"
        unit: 'm/s'
        acronym: 'WIND'
      rain:
        description: "Rain in mm per 3 hours"
        type: "number"
        unit: "mm"
        acronym: 'RAIN'
      snow:
        description: "Snow in mm per 3 hours"
        type: "number"
        unit: "mm"
        acronym: 'SNOW'

    status: "None"
    temperature: null
    humidity: null
    pressure: null
    windspeed: null
    rain: null
    snow: null

    constructor: (@config) ->
      @id = config.id
      @name = config.name
      @location = config.location
      @lang = config.lang
      @units = config.units
      @timeout = config.timeout
      super()
      @requestForecast()

    requestForecast: () =>
      request = PromiseRetryer.run(
        delay: 1000,
        maxRetries: 5,
        promise: => weatherLib.nowAsync( q: @location, lang: @lang, units: @units )
      ).then( (result) =>
        handleError(result)
        if result.weather?
          @_setAttribute "status", result.weather[0].description
        if result.main?
          @_setAttribute "temperature", Number result.main.temp.toFixed(1)
          @_setAttribute "humidity", Number result.main.humidity.toFixed(1)
          @_setAttribute "pressure", Number result.main.pressure.toFixed(1)
        if result.wind?
          @_setAttribute "windspeed", Number result.wind.speed.toFixed(1)
        @_setAttribute "rain", if result.rain? then Number result.rain[Object.keys(result.rain)[0]] else 0.0
        @_setAttribute "snow", if result.snow? then Number result.snow[Object.keys(result.rain)[0]] else 0.0
        @_currentRequest = Promise.resolve()
        setTimeout(@requestForecast, @timeout)
      ).catch( (err) =>
        env.logger.error(err.message)
        env.logger.debug(err.stack)
        setTimeout(@requestForecast, @timeout)
      )
      request.done()
      @_currentRequest = request unless @_currentRequest?
      return request

    _setAttribute: (attributeName, value) ->
      unless @[attributeName] is value
        @[attributeName] = value
        @emit attributeName, value

    getStatus: -> @_currentRequest.then(=> @status )
    getTemperature: -> @_currentRequest.then(=> @temperature )
    getHumidity: -> @_currentRequest.then(=> @humidity )
    getPressure: -> @_currentRequest.then(=> @pressure )
    getWindspeed: -> @_currentRequest.then(=> @windspeed )
    getRain: -> @_currentRequest.then(=> @rain )
    getSnow: -> @_currentRequest.then(=> @snow )

  class OpenWeatherForecastDevice extends env.devices.Device
    attributes:
      forecast:
        description: "The expected forecast"
        type: "string"
      low:
        description: "The minimum temperature"
        type: "number"
        unit: '°C'
        acronym: 'LOW'
      high:
        description: "The maximum temperature"
        type: "number"
        unit: '°C'
        acronym: 'HIGH'
      humidity:
        description: "The expected humidity"
        type: "number"
        unit: '%'
        acronym: 'RH'
      pressure:
        description: "The expected pressure"
        type: "number"
        unit: 'mbar'
        acronym: 'P'
      windspeed:
        description: "The wind speed"
        type: "number"
        unit: 'm/s'
        acronym: 'WIND'
      rain:
        description: "Rain in mm per 3 hours"
        type: "number"
        unit: "mm"
        acronym: 'RAIN'
      snow:
        description: "Snow in mm per 3 hours"
        type: "number"
        unit: "mm"
        acronym: 'SNOW'

    forecast: "None"
    low: null
    high: null
    humidity: null
    pressure: null
    windspeed: null
    rain: null
    snow: null

    constructor: (@config) ->
      @id = config.id
      @name = config.name
      @location = config.location
      @lang = config.lang
      @units = config.units
      @timeout = config.timeout
      @day = config.day
      super()
      @requestForecast()

    requestForecast: () =>
      request = PromiseRetryer.run(
        delay: 1000,
        maxRetries: 5,
        promise: =>
          weatherLib.forecastAsync( q: @location, lang: @lang, units: @units, cnt: @day )
      ).then( (result) =>
        handleError(result)
        if result.list?
          dateStart = new Date
          dateEnd = new Date
          dateStart.setDate(dateStart.getDate() + @day)
          dateEnd.setDate(dateEnd.getDate() + @day)
          dateStart.setHours 0
          dateStart.setMinutes 0
          dateStart.setSeconds 0
          dateEnd.setHours 23
          dateEnd.setMinutes 59
          dateEnd.setSeconds 59
          temp_min = +Infinity
          temp_max = -Infinity

          i = 0
          while i < result.list.length
            d = new Date(result.list[i].dt_txt)
            if dateStart <= d and d <= dateEnd
              if result.list[i].main.temp_min <= temp_min
                temp_min = result.list[i].main.temp_min
              if result.list[i].main.temp_max >= temp_max
                temp_max = result.list[i].main.temp_max
            i++

          @_setAttribute "low", Number temp_min.toFixed(1)
          @_setAttribute "high", Number temp_max.toFixed(1)

          if result.list[8*@day]?
            if result.list[8*@day].weather?
              @_setAttribute "forecast", result.list[8*@day].weather[0].description
            if result.list[8*@day].main?
              @_setAttribute "humidity", Number result.list[8*@day].main.humidity.toFixed(1)
              @_setAttribute "pressure", Number result.list[8*@day].main.pressure.toFixed(1)
            if result.list[8*@day].wind?
              @_setAttribute "windspeed", Number result.list[8*@day].wind.speed.toFixed(1)
            @_setAttribute "rain", (
              if result.list[8*@day].rain? then Number result.list[8*@day].rain['3h'] else 0.0
            )
            @_setAttribute "snow", (
              if result.list[8*@day].snow? then Number result.list[8*@day].snow['3h'] else 0.0
            )
        @_currentRequest = Promise.resolve()
        setTimeout(@requestForecast, @timeout)
      ).catch( (err) =>
        env.logger.error(err.message)
        env.logger.debug(err.stack)
        setTimeout(@requestForecast, @timeout)
      )
      request.done()
      @_currentRequest = request unless @_currentRequest?
      return request

    _setAttribute: (attributeName, value) ->
      unless @[attributeName] is value
        @[attributeName] = value
        @emit attributeName, value

    getForecast: -> @_currentRequest.then(=> @forecast )
    getLow: -> @_currentRequest.then(=> @low )
    getHigh: -> @_currentRequest.then(=> @high )
    getHumidity: -> @_currentRequest.then(=> @humidity )
    getPressure: -> @_currentRequest.then(=> @pressure )
    getWindspeed: -> @_currentRequest.then(=> @windspeed )
    getRain: -> @_currentRequest.then(=> @rain )
    getSnow: -> @_currentRequest.then(=> @snow )

  plugin = new OpenWeather
  return plugin
