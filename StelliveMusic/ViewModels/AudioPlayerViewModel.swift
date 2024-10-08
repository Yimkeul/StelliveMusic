//
//  AudioPlayerViewModel.swift
//  StelliveMusic
//
//  Created by yimkeul on 9/7/24.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import Kingfisher

class AudioPlayerViewModel: ObservableObject {

    enum PlayMode {
        case isInfinityMode
        case isOneSongInfinityMode
        case isDefaultMode
    }



    @Published var filteredSongs: [Song] = []
    @Published var currentSong: Song?

    // 재생 시간 관련 프로퍼티
    @Published private(set) var duration: TimeInterval = 0.0
    @Published private(set) var currentTime: TimeInterval = 0.0
    @Published var isScrubbingInProgress: Bool = false // 슬라이더 드래그 중인지 여부
    @Published var isSeekInProgress: Bool = false // seek 작업이 진행 중인지 여부

    // 재생 모드 관련 (셔플, 무한 반복, 1곡 반복, 1회전)
    @Published var playMode: PlayMode = .isDefaultMode
    @Published var isShuffleMode: Bool = false

    @Published var player: AVQueuePlayer?
    private var waitingSongs: [Song] = []
    private var timeObserver: Any?

    var cancellables = Set<AnyCancellable>()
    var isPlaying = false


    init() {
        setupNotificationObservers()
    }
    // MARK: Setup Notification Observer

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleSongDidFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }


    @objc private func handleSongDidFinishPlaying(_ notification: Notification) {
        removePeriodicTimeObserver()
        if let finishedItem = notification.object as? AVPlayerItem {
            player?.remove(finishedItem)
        }
        guard let finishedSong = currentSong else { return }
        finishedSong.playerState = .stopped
        // MARK: CHEKCING
//        print("Fin")
//        checkQueueItems()

//        guard let nextSong = getNextSong(for: finishedSong) else { return }

        guard let currentPlayerItem = self.player?.currentItem?.asset as? AVURLAsset else {
            return
        }

        let currentPlayerURL = currentPlayerItem.url.absoluteString
        guard let nextSong = waitingSongs.first(where: { $0.songInfo.mp3Link == currentPlayerURL }) else { return }

        switch playMode {
        case .isDefaultMode:
            handleDefaultMode(with: nextSong)
        case .isInfinityMode:
            handleInfinityMode(with: nextSong)
        case .isOneSongInfinityMode:
            // TODO: Implement one song infinite loop logic
            break
        }

    }
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue), type == .began else {
            return
        }
        pauseAudio()
    }

    // MARK: - Song Completion Logic

    private func handleDefaultMode(with nextSong: Song) {
        if nextSong == self.waitingSongs.first {
            currentSong?.playerState = .stopped
        } else if nextSong != self.waitingSongs.first {
            handleReadyNextSong(nextSong: nextSong)
        }
    }

    private func handleInfinityMode(with nextSong: Song) {
        if nextSong == self.waitingSongs.first {
            //한바퀴 재생 완료
            if isShuffleMode {
                playAllShuffleAudio()
            } else {
                playAllAudio()
            }
        } else {
            handleReadyNextSong(nextSong: nextSong)
        }
    }

    private func handleReadyNextSong(nextSong: Song) {
        checkQueueItems()

//        guard let currentPlayerItemURl = self.player?.currentItem?.asset as? AVURLAsset else {
//            return
//        }
//        if currentPlayerItemURl.url.absoluteString != nextSong.songInfo.mp3Link {
////            playAudio(selectSong: nextSong)
////            player?.replaceCurrentItem(with: AVPlayerItem(url: URL))
//
//            player?.replaceCurrentItem(with: AVPlayerItem(url: URL(string:
//                nextSong.songInfo.mp3Link
//            )!))
//            print("CHECK TIME")
//        }
        currentSong = nextSong
        currentSong?.playerState = .playing
        addPeriodicTimeObserver()
        updateNowPlayingInfo()
    }

// array에서 index를 맨앞으로 하고 나머지는 shuffle
    func shuffleExceptIndex<T>(array: [T], index: Int) -> [T] {
        let element = array[index]
        var remainingArray = array
        remainingArray.remove(at: index)
        remainingArray.shuffle()
        return [element] + remainingArray
    }
}

// MARK: MusicPlayer 전체 재생 관련
extension AudioPlayerViewModel {

    func updateCurrentSong() {
        removePeriodicTimeObserver()
        self.currentSong?.playerState = .paused
        guard let currentPlayerItem = self.player?.currentItem?.asset as? AVURLAsset else {
            return
        }
        let currentPlayerURL = currentPlayerItem.url.absoluteString
        guard let currentSong = waitingSongs.first(where: { $0.songInfo.mp3Link == currentPlayerURL }) else { return }
        self.currentSong = currentSong
        self.currentSong?.playerState = .playing
        addPeriodicTimeObserver()
        updateNowPlayingInfo()
    }


    func playAllAudio() {
        if filteredSongs.isEmpty { return }
        clearAVPlayer()
        isShuffleMode = false
        prepareQueue()
        startPlay()
    }

    func playAudio(selectSong: Song) {

        if player == nil {
            player = AVQueuePlayer()
        }

        if currentSong == selectSong && player?.currentItem?.status == .readyToPlay {
            player?.play()
            isPlaying = true
            currentSong?.playerState = .playing
            addPeriodicTimeObserver()
            updateNowPlayingInfo()
            return
        }

        clearAVPlayer()

        guard let selectedIndex = filteredSongs.firstIndex(of: selectSong) else { return }

        self.waitingSongs = isShuffleMode
            ? shuffleExceptIndex(array: filteredSongs, index: selectedIndex)
        : filteredSongs

        if isShuffleMode {
            let items = self.waitingSongs.map {
                AVPlayerItem(url: URL(string: $0.songInfo.mp3Link)!)
            }
            player = AVQueuePlayer(items: items)
            currentSong = self.waitingSongs.first
        } else {
            player?.insert(AVPlayerItem(url: URL(string: self.waitingSongs[selectedIndex].songInfo.mp3Link)!), after: nil)

            for index in selectedIndex + 1 ..< self.waitingSongs.count {
                let item = AVPlayerItem(url: URL(string: self.waitingSongs[index].songInfo.mp3Link)!)
                player?.insert(item, after: nil)
            }
            currentSong = selectSong
        }
        startPlay()
    }

    func playAllShuffleAudio() {
        if filteredSongs.isEmpty {
            return
        }
        clearAVPlayer()
        isShuffleMode = true
        prepareQueue()
        startPlay()
    }

    func prepareQueue() {
        if player == nil {
            player = AVQueuePlayer()
        }
        self.waitingSongs = isShuffleMode ? filteredSongs.shuffled() : filteredSongs

        guard !self.waitingSongs.isEmpty else { return }
        let items = self.waitingSongs.map {
            AVPlayerItem(url: URL(string: $0.songInfo.mp3Link)!)
        }
        player = AVQueuePlayer(items: items)
        currentSong = waitingSongs.first
        // MARK: CHEKCING
//        checkQueueItems()
    }


    private func isCurrentSongReadyToPlay(_ song: Song) -> Bool {
        return currentSong == song && player?.currentItem?.status == .readyToPlay
    }

    private func resumePlay() {
        currentSong?.playerState = .playing
        isPlaying = true
        player?.play()
    }

    func startPlay() {
        resumePlay()
        addPeriodicTimeObserver()
        updateNowPlayingInfo()
    }

    func playNextAudio() {
        let targetTime = CMTime(seconds: max(self.duration - 1, 0), preferredTimescale: 600) // 끝시간에서 1초를 뺀 시간으로 변환
        player?.seek(to: targetTime)
        // MARK: CHEKCING
//        checkQueueItems()
    }

    func playPreviousAudio() {
        guard let currentSong = currentSong else {
            print("현재 재생 중인 곡이 없습니다.")
            return
        }

        // 현재 재생 시간이 1초 이상이면 현재 곡 처음으로 이동
        if currentTime > 1 {
            seekToTime(0) // 0초로 이동
            return
        }

        guard let currentIndex = self.waitingSongs.firstIndex(of: currentSong) else {
            print("현재 곡이 waitingSongs에 없습니다.")
            return
        }

        if isShuffleMode {
            // 셔플 모드에서는 첫 곡에서 이전 곡 재생 시 재생 멈춤
            if currentIndex == 0 {
                stopPlayback() // 재생 멈춤 함수 호출
            } else {
                // 이전 곡을 재생
                let previousSong = waitingSongs[currentIndex - 1]
                playAudio(selectSong: previousSong)
            }
            return
        }

        // PlayMode에 따른 동작
        switch playMode {
        case .isDefaultMode:
            if currentIndex == 0 {
                stopPlayback() // 처음 곡에서 이전 곡 재생 시 멈춤
            } else {
                let previousSong = waitingSongs[currentIndex - 1]
                playAudio(selectSong: previousSong)
            }

        case .isInfinityMode:
            // 처음 곡에서 이전 곡을 재생하면 마지막 곡으로 이동
            let previousIndex = (currentIndex - 1 + waitingSongs.count) % waitingSongs.count
            let previousSong = waitingSongs[previousIndex]
            playAudio(selectSong: previousSong)

        case .isOneSongInfinityMode:
            // 나중에 구현할 내용
            break
        }
    }

    private func stopPlayback() {
        player?.pause()
        isPlaying = false
        currentSong?.playerState = .stopped
    }

    func pauseAudio() {
        player?.pause()
        isPlaying = false
        currentSong?.playerState = .paused
    }

    func clearAVPlayer() {
        removePeriodicTimeObserver() // 초단위 초기화
        player?.pause() // 플레이어 정지
        player?.removeAllItems() // 플레이어 초기화
    }

    func getNextSong(for song: Song) -> Song? {
        guard let currentIndex = self.waitingSongs.firstIndex(of: song) else { return nil }
        let nextIndex = (currentIndex + 1) % self.waitingSongs.count
        return self.waitingSongs[nextIndex]
    }
}

// MARK: playMode 관련
extension AudioPlayerViewModel {
    func shuffleModeToggle() {
        isShuffleMode.toggle()
        setQueue()
    }

    func setQueue() {
        guard let currentSong = currentSong, let currentIndex = filteredSongs.firstIndex(of: currentSong) else { return }

        waitingSongs = isShuffleMode ? shuffleExceptIndex(array: filteredSongs, index: currentIndex) : Array(filteredSongs[currentIndex...])

        updateQueue()
    }

    func updateQueue() {
        // 현재 플레이어에 있는 대기열을 가져옴
        guard let currentItems = player?.items(), !currentItems.isEmpty else { return }

        for i in 1 ..< currentItems.count {
            player?.remove(currentItems[i])
        }

        for i in 1 ..< self.waitingSongs.count {
            let item = AVPlayerItem(url: URL(string: self.waitingSongs[i].songInfo.mp3Link)!)
            player?.insert(item, after: nil)
        }
    }

    func repeatModeToggle() {
        if playMode == .isDefaultMode {
            playMode = .isInfinityMode
        } else if playMode == .isInfinityMode {
            playMode = .isDefaultMode
        } else {
            playMode = .isDefaultMode
        }
    }

}


// MARK: - 시간 관찰자 관리
extension AudioPlayerViewModel {
    private func addPeriodicTimeObserver() {
        // 중복 등록 방지
        guard timeObserver == nil else { return }

        let interval = CMTime(value: 1, timescale: 1)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            if self.isScrubbingInProgress || self.isSeekInProgress { return }

            let newCurrentTime = time.seconds
            let newDuration = self.player?.currentItem?.duration.seconds ?? 0.0

            if newCurrentTime.isFinite && !newCurrentTime.isNaN {
                self.currentTime = newCurrentTime
            }

            if newDuration.isFinite && !newDuration.isNaN {
                self.duration = newDuration
            }

            self.updateNowPlayingInfo()
        }

    }

    private func removePeriodicTimeObserver() {
        // 옵저버가 없으면 아무 것도 하지 않음
        guard let timeObserver = timeObserver else { return }

        // 옵저버 해제
        player?.removeTimeObserver(timeObserver)
        self.timeObserver = nil
        self.currentTime = 0.0
        self.duration = 0.0
    }

    func setCurrentTime(_ time: TimeInterval) {
        guard time.isFinite && !time.isNaN else { return }
        self.currentTime = time

        if let player = player {
            let newTime = CMTime(seconds: time, preferredTimescale: 600) // Timescale을 더 세밀하게 조정
            player.seek(to: newTime)
        }
    }

    func seekToTime(_ time: TimeInterval) {
        guard let player = player else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)

        // Seek 작업이 진행 중임을 표시
        isSeekInProgress = true

        player.seek(to: targetTime) { [weak self] completed in
            if completed {
                self?.isScrubbingInProgress = false // 슬라이더 드래그 중지
                self?.isSeekInProgress = false // seek 작업 완료
                self?.currentTime = time // seek 완료 후 실제 currentTime 반영
            }
        }
    }

}

// MARK: SongList에 필요한 함수 (가수 이름 생성, 노래 리스트 필터)
extension AudioPlayerViewModel {
    func makeSinger(_ singers: [String]) -> String {
        return singers.joined(separator: " & ")
    }

    func filterSongs(songInfoItems: [Song], selectedSongType: SongType, stellaName: String) {
        let temp = stellaName == "스텔라이브" ? songInfoItems : songInfoItems.filter { $0.songInfo.singer.contains(stellaName) }
        filteredSongs = selectedSongType == .all ? temp.sorted { $0.songInfo.registrationDate > $1.songInfo.registrationDate }:
            temp.filter { $0.songInfo.songType == selectedSongType.rawValue }.sorted { $0.songInfo.registrationDate > $1.songInfo.registrationDate }
    }

    func getPlayerIcon(for item: Song) -> String {
        if currentSong == item {
            switch item.playerState {
            case .playing:
                return "pause.fill"
            case .paused, .stopped:
                return "play.fill"
            }
        }
        return "play.fill"
    }

    func getPlayerModeIcon() -> String {
        if playMode == .isDefaultMode {
            return "repeat.circle"
        } else if playMode == .isInfinityMode {
            return "repeat.circle.fill"
        } else {
            return "repeat.circle"
        }
    }

    func controlPlay(_ item: Song) {
        if item == currentSong {
            if item.playerState == .playing {
                pauseAudio()
            } else {
                playAudio(selectSong: item)
            }
        } else {
            playAudio(selectSong: item)
        }
    }
}

// MARK: 제어센터 관련
extension AudioPlayerViewModel {

    func MPNowPlayingInfoCenterSetting() {
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let center = MPRemoteCommandCenter.shared()

        // 재생, 일시정지 버튼 활성화
        center.playCommand.addTarget { [weak self] _ in
            guard let self = self, let song = self.currentSong else { return .commandFailed }
            self.playAudio(selectSong: song) // 선택된 곡 재생
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.pauseAudio() // 일시정지
            return .success
        }

        // 다음 곡으로 넘어가는 스킵 기능
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNextAudio() // 다음 곡 재생
            return .success
        }

        // 이전 곡으로 돌아가는 스킵 기능
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPreviousAudio() // 이전 곡 재생
            return .success
        }

        // 커맨드 활성화
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
    }

    private func updateNowPlayingInfo() {
        guard let currentSong = currentSong else {
            return
        }

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()
        let singerName = makeSinger(currentSong.songInfo.singer)

        nowPlayingInfo[MPMediaItemPropertyTitle] = currentSong.songInfo.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = singerName

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds

        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = player?.currentItem?.duration.seconds

        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0 // 재생 중이면 1.0, 일시 정지 상태면 0.0

        if let artworkURL = URL(string: currentSong.songInfo.thumbnail) {
            KingfisherManager.shared.retrieveImage(with: artworkURL) { result in
                switch result {
                case .success(let value):
                    let artworkImage = value.image
                    let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in
                        return artworkImage
                    }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork

                case .failure(let error):
                    print("Failed to download image: \(error.localizedDescription)")
                }

                // 업데이트 완료 후 NowPlayingInfo 설정
                nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
            }
        } else {
            // URL이 없으면 NowPlayingInfo 바로 업데이트
            nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo

        }
    }
}

// MARK: 테스트 코드
extension AudioPlayerViewModel {

    func checkCurrentSong() {
        self.$currentSong
            .receive(on: DispatchQueue.main)
            .sink {
            guard let currentPlayerItemURl = self.player?.currentItem?.asset as? AVURLAsset else {
                return
            }
            if currentPlayerItemURl.url.absoluteString != $0!.songInfo.mp3Link {
                self.player?.replaceCurrentItem(with: AVPlayerItem(url: URL(string:
                    self.currentSong!.songInfo.mp3Link
                )!))
            }
        }
            .store(in: &cancellables)
    }


    func checkQueueItems() {
        if let currentItem = self.player?.currentItem {
            let title = checkTitle(item: currentItem)
            print("현재 재생 중인 곡: \(title)")
        }

        if let remainingItems = self.player?.items() {
            print("Queue Count : \(remainingItems.count)")
            for item in remainingItems {
                let title = checkTitle(item: item)
                print("\(title)", terminator: " / ")
            }
        }
        print()
        if !waitingSongs.isEmpty {
            print("waitingSong : \(waitingSongs.count)")
            for item in waitingSongs {
                print("\(item.songInfo.title)", terminator: " - ")
            }
        }
    }

    func checkTitle(item: AVPlayerItem) -> String {
        if let target = item.asset as? AVURLAsset {
            guard let item = self.waitingSongs.first(where: {
                $0.songInfo.mp3Link == target.url.absoluteString
            }) else { return "" }
            return item.songInfo.title
        } else {
            return ""
        }
    }
}


