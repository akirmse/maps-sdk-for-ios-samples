//
//  WeatherRadarTileProvider.swift
//  Peakbagger
//
//  Created by Andrew Kirmse on 12/8/18.
//  Copyright © 2018 Mountainside. All rights reserved.
//

import GoogleMaps

// Rainviewer API: https://www.rainviewer.com/api.html
//
// Tile URLs contain a timestamp that is updated every 10 minutes.
//
// There is a special URL we periodically fetch to get the latest available timestamps for each
// frame of the animation.  These are stored in StoredValues so they don't need to be continually
// refetched.
//
// Given a frame number of the animation, we modulo it by the number of timestamps to get
// the timestamp for the currently visible images, and we use this timestamp to fetch the
// images themselves.
//
// In order to avoid refetching the images constantly as the animation loops, we store
// them in a disk cache.

class WeatherRadarTileProvider: GMSTileLayer {
    private static let MAX_DATA_AGE_SECONDS = 5.0 * 60.0

    private static let RAINVIEWER_URL_TEMPLATE = "https://tilecache.rainviewer.com/v2/radar/%d/%d/%d/%d/%d/4/1_1.png"
    private static let RAINVIEWER_TIMESTAMP_URL = "https://tilecache.rainviewer.com/api/maps.json"

    // Tiles are downloaded in parallel, so it's possible for multiple threads to realize that
    // the timestamp is old.  We only want to fetch it once, however.  So we have a semaphore
    // that each tile download should try to grab before fetching the timestamp from the server.
    private let semaphore = DispatchSemaphore(value: 1)

    private var frameNumber = 0
    private var currentTimestamp: Int64 = 0
    private var session: URLSession
    
    private var lastWeatherTimestamps = ""
    private var lastCheckTime: TimeInterval = 0

    init(frameNumber: Int) {
        self.session = URLSession(configuration: .default)
        self.frameNumber = frameNumber
        super.init()
    }

    // Fetch the given tile, magnifying a coarser tile if necessary
    override func requestTileFor(x: UInt, y: UInt, zoom: UInt, receiver: (GMSTileReceiver)) {
        self.maybeUpdateTimestampInBackground()

        let url = getTileUrl(x: Int(x), y: Int(y), zoom: Int(zoom), timestamp: self.currentTimestamp)
        self.fetchTile(x: x, y: y, zoom: zoom, url: url, receiver: receiver)
    }
    
    // Return the UNIX epoch timestamp of the data for the current animation frame, or 0 if none.
    func getCurrentTimestamp() -> Int64 {
        let timestamps = lastWeatherTimestamps
        return parseTimestampFromTimestampList(timestamps: timestamps, frameNumber: self.frameNumber)
    }
    
    private func maybeUpdateTimestampInBackground() {
        // Do we need to refresh timestamp?
        let lastCheckTime = self.lastCheckTime
        let now = Date().timeIntervalSince1970
        self.currentTimestamp = parseTimestampFromTimestampList(
            timestamps: lastWeatherTimestamps, frameNumber: self.frameNumber)
        if now - lastCheckTime > Self.MAX_DATA_AGE_SECONDS {
            // Use latest timestamp if we can get it; fall back to previous if not
            self.getLatestTimestamp() { newTimestamp in
                if newTimestamp != 0 {
                    self.currentTimestamp = newTimestamp
                }
            }
        }
    }

    private func getTileUrl(x: Int, y: Int, zoom: Int, timestamp: Int64) -> String {
        let tileSize = 512
        return String(format: Self.RAINVIEWER_URL_TEMPLATE, timestamp, tileSize, zoom, x, y)
    }

    // Invoke the callback with the UNIX epoch timestamp of the data for the
    // current animation frame, or 0 on failure. It may have to be fetched from the network.
    private func getLatestTimestamp(callback: @escaping (Int64) -> ()) {
        self.semaphore.wait()

        // Maybe someone else got the timestamp already?
        let lastCheckTime = self.lastCheckTime
        let timestamp = parseTimestampFromTimestampList(
            timestamps: lastWeatherTimestamps, frameNumber: self.frameNumber)
        let now = Date().timeIntervalSince1970
        if now - lastCheckTime > Self.MAX_DATA_AGE_SECONDS {
            // Timestamp is still old; go fetch it ourselves
            fetchLatestTimestamps() { newTimestamps in
                if let newTimestamps = newTimestamps {
                    self.lastCheckTime = now
                    self.lastWeatherTimestamps = newTimestamps
                    callback(self.parseTimestampFromTimestampList(
                        timestamps: newTimestamps, frameNumber: self.frameNumber))
                } else {
                    // Fall back to older timestamp if we couldn't get new one
                    callback(timestamp)
                }
                self.semaphore.signal()
            }
            return
        }

        self.semaphore.signal()

        // Existing timestamp is still current
        callback(timestamp)
    }

    // Call callback with comma-separated list of UNIX timestamps corresponding to available frames
    // of the radar animation, or nil on failure.
    private func fetchLatestTimestamps(callback: @escaping (String?) -> ()) {
        // Last N timestamps available at a URL.  Example:
        // [1544143200,1544143800,1544144400,1544145000,1544145600,1544146200,1544146800,1544147400,1544148000,1544148600,1544149200,1544149800,1544150400]
        NetworkUtils.fetchUrlToString(Self.RAINVIEWER_TIMESTAMP_URL) { data in
            guard let data = data else {
                callback(nil)
                return
            }

            callback(data.replacingOccurrences(of: "]|\\[", with: "", options: .regularExpression))
        }
    }
    
    // Return UNIX timestamp from comma-separated list, based on a frame number that cycles
    // through the available timestamps.  Return 0 on failure.
    private func parseTimestampFromTimestampList(timestamps: String, frameNumber: Int) -> Int64 {
        let components = timestamps.split(separator: ",")
        if components.isEmpty {
            return 0
        }

        // Cycle through available frames in increasing time order, fetching the most recent one
        // (last in array) first in the hopes that we may display it first.
        let index = ((frameNumber + components.count - 1) % components.count)
        let component = components[index]
        
        if let longVal = Int64(component) {
            return longVal
        }

       // log.debug("Couldn't parse time epoch from \(timestamps)")
        return 0
    }
    
    // Fetch tile from the given URL, or the cache if enabled.  This is an internal function.
    func fetchTile(x: UInt, y: UInt, zoom: UInt, url: String, receiver: (GMSTileReceiver)) {
        let request = NSMutableURLRequest(url: URL(string: url)!)
        request.timeoutInterval = 5

        let urlRequest = request as URLRequest
        self.session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                // log.warning("Couldn't fetch url \(urlRequest.url!), error = \(error)")
                receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: nil)
            } else {
                if let data = data, let image = UIImage(data: data) {
                    receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: image)
                } else {
                    receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: nil)
                }
            }
        }.resume()
    }
}
