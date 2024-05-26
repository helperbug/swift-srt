# swift-srt


Secure Reliable Transport (SRT) is now a first-class citizen in Apple's ecosystem! This Swift package is implemented using NWFramerProtocol and Apple’s native networking framework. Designed for modern standards, it excels in live streaming, video on demand, and two-way communication applications by providing reactive "hints" to automate peak quality based on network conditions. 

Key features include:

- Seamless integration with Swift and Apple's frameworks

- Compatibility with SwiftUI applications

- Strict adherence to the SRT specification

- Support for both delegate pattern and Combine publishers

- DocC

With swift-srt, developers can seamlessly integrate high-quality, low-latency streaming capabilities into their Swift applications, leveraging the latest advancements in Apple’s networking and multimedia frameworks.  

This open-source project is public-domain. The design emphasizes simplicity and utility, following the principles of Occam's Razor.

  

# Connection

  

The SRT Connection is implemented as a UDP NWConnection with a custom NWFramer. The frames, lifecycle and operations of SRT are managed internally. Connections can handle multiple streams identified by a SocketID. When the last socket is shut down, the connection ends.

  

## ListenerSession

  

The `ListenerSession` manages and accepts incoming connection requests. It is designed for servers that need to handle multiple connections, such as in meeting software where many participants connect to a central server. The listener waits for connection attempts, authenticates them, and establishes secure sessions for data reception.

  

## CallerSession

  

The `CallerSession` initiates connections to a listener. It is suitable for clients that need to connect to a specific server, like a meeting participant joining a session. The caller handles the handshake process, ensuring both parties agree on the connection parameters and establish a secure session for data transmission.

  

## Rendezvous

  

Rendezvous mode is useful when there are firewalls between two SRT endpoints. Both parties initiate the connection simultaneously, making it ideal for peer-to-peer scenarios where each endpoint may be behind NATs or firewalls. Firewalls see the two participants trying to connect and poke a temporary hole in the firewall, allowing a peer-to-peer connection. This mode facilitates dynamic connection establishment without requiring a predefined client-server relationship.

  

### Handshake and Induction

  

The handshake process is crucial for establishing a secure and reliable connection in SRT. It involves several steps to ensure both parties agree on the connection parameters and security settings.

  

#### Caller-Listener Handshake

  

**Induction Phase**:

- **Caller**: Sends an induction request to the listener.

- **Listener**: Responds with an induction response, including a cookie for security purposes.

  

**Conclusion Phase**:

- **Caller**: Sends a conclusion request with the received cookie.

- **Listener**: Confirms the connection by responding to the conclusion request.

  

#### Rendezvous Handshake

  

**Waving State**:

- Both parties start by sending a waveband handshake packet, including their respective cookies.

  

**Conclusion**:

- Each peer receives the other's cookie and performs the cookie contest to determine roles.

- The initiator sends a conclusion request, and the responder replies, finalizing the connection.

  

If the handshakes fails the connection is closed and after a short delay the handshake process starts over. Upon success the connection is hosting a single SocketID that sends keep-alive packets along with any data packets. Additional streams may be created and once the last one is shutdown the connection is closed.

  

---

  

### Encryption

  

Encryption in the swift-srt package is optional and employs AES-CTR (Advanced Encryption Standard in Counter mode) for securing data transmission. During the handshake process, the caller creates keys and sends them to the listener. This includes the wrapped stream encrypting key (SEK) and necessary cryptographic parameters. The responder decrypts the SEK to establish a secure connection.

  

In two-way communication scenarios, each endpoint uses its own Key Encrypting Key (KEK) to encrypt outgoing and decrypt incoming messages. This bidirectional encryption ensures both parties can securely exchange data. The encryption keys are periodically refreshed to maintain security throughout the connection, and this key management is handled automatically by the protocol.

  

### Sockets and Auto-Performance Tuning

  

Each socket is uniquely identified by its own SocketID and maintains its own cryptographic keys, so each stream is isolated and secure. Sockets are responsible for tracking their own metrics that enables fine-grained monitoring and optimization of data transmission. Sockets also manage ACKs, NACKs, KeepAlive and other SRT details to maintain the data flow, retransmission and metrics.

  

### Metrics

  

Metrics are a key part of SRT and monitor the performance of data transmission and auto-buffer based on target delay.

  

#### Performance Metrics

  

1. **Bandwidth Usage**: The amount of data transmitted over the network per unit time.

2. **Packet Loss Rate**: The percentage of packets lost during transmission.

3. **Round-Trip Time (RTT)**: The time it takes for a packet to travel from the sender to the receiver and back. It is used to measure latency and network performance.

  

#### Quality Metrics

  

1. **Jitter**: The variation in packet arrival times. Lower jitter indicates a more stable and consistent data stream, which is ideal for real-time streaming.

2. **Latency**: The delay between sending and receiving data packets. Managing latency is one of the key benefits of SRT and this package.

  

#### Reliability Metrics

  

1. **ACK Count**: The number of acknowledgments received. This metric helps in understanding the responsiveness of the receiver.

2. **Retransmission Count**: The number of packets retransmitted due to loss or error. High retransmission counts can indicate network issues or instability.

  

#### Connection Metrics

  

1. **Keep-Alive Messages**: Sent once per second per socket are an easy way to keep track of uptime.

2. **Socket State**: The current state of the socket, which helps in diagnosing connection issues and understanding the lifecycle of the connection.

  

Each socket in tracks metrics independently for detailed monitoring and performance tuning of individual streams. These metrics are monitored internally and also published, so you can optimize and visualize current context.

  

### Common Uses, Flavors, and Hints

  

#### Common Uses

  

SRT is versatile and can be used for various types of data transmission:

- **Audio Streaming**: Transmitting audio data with peak quality, low latency and high reliability.

- **Audio and Video Streaming**: Handling both audio and video streams simultaneously for live broadcasts, video conferencing, and video on demand.

- **Screen Sharing**: Facilitating the real-time sharing of a user’s screen, useful for presentations, remote support, and collaborative work.

- **Still Image Transmission**: Sending high-resolution still images, useful for applications like digital signage and remote photography.

- **Data Broadcasting**: Broadcasting data to multiple endpoints efficiently, ideal for live events and real-time data feeds.

- **Surveillance and Security Feeds**: Ensuring secure and reliable transmission of video feeds from security cameras.

  

#### Flavors

  

SRT supports a range of configuration options, or "flavors," to optimize streaming quality based on the specific needs of the application:

- **Audio Bitrate**: Adjusting the amount of data transmitted per second for audio, affecting quality and bandwidth usage.

- **Compression Quality**: Modifying the level of compression applied to audio and video data, balancing between file size and quality.

- **Bit-Depth**: Setting the number of bits used to represent audio samples, influencing sound quality.

- **Framerate**: Configuring the number of video frames transmitted per second, impacting smoothness and realism of video playback.

- **Frame Resolution**: Determining the dimensions of video frames, affecting clarity and detail.

  

#### Hints

  

Hints in the swift-srt package provide insights beyond the standard SRT specifications, helping to optimize performance based on real-world usage:

- **Supported Flavors**: Hints suggest which combinations of flavors (e.g., specific bitrates, resolutions) are viable based on current network conditions and empirical usage data.

  

#### Example of a Hint

  

**High Resolution Streaming**: When aiming for high-resolution streaming (e.g., 4K video), the hint system can analyze current network conditions and metrics to suggest the optimal bitrate and frame rate. Without hints, you would need to experiment manually, testing different bitrates and resolutions, and monitor for buffering, lag, or dropped frames. Hints streamline this process by providing empirically derived recommendations based on actual network performance data.

  

**High Bitrate Audio**: For applications focusing on high-fidelity audio streaming, hints can recommend appropriate bitrates and compression settings to maintain audio quality. Audio data is small and hints make it easy to use the highest quality coder available.

  

### How to Use

  

Hints in the swift-srt package provide real-time, data-driven insights to optimize performance based on current network conditions, making it easy to use advanced streaming features and technologies:

  

#### 5K Screen Sharing

Apple's VideoToolbox for high-quality screen sharing:

- **Hint**: Metrics show 35 Mbps available bandwidth and low latency. Ideal for 5K resolution screen sharing.

- **Action**: Use H.265 encoding for crystal-clear, high-resolution screen sharing.

  

#### 96-bit Audio Streaming

Deliver high-fidelity audio for music or communication:

- **Hint**: Network conditions allow for high bitrate audio streaming.

- **Action**: Configure audio settings for 96-bit depth to ensure rich, immersive sound.

  

#### HDR 60-fps 10-bit Video

Stream live video with stunning detail and smooth playback:

- **Hint**: Stable network with 30 Mbps bandwidth and low latency detected.

- **Action**: Use H.265 encoding at 60 fps with 10-bit color depth for vibrant, lifelike video.

  

Subscribe to the hint stream to reactively adjust encoder quality based on real-time network conditions. As the network degrades, the hints suggest stepping down the encoder quality to maintain stability. When conditions improve, it scales back to full quality automatically, showcasing Apple’s technology at its best without manual intervention. 
