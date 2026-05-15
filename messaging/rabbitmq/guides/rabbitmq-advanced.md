# RabbitMQ Advanced Reference - Official Documentation Extract

Source: https://www.rabbitmq.com/docs (fetched 2026-04-08)

---

## Table of Contents

1. [Queue Types Comparison](#1-queue-types-comparison)
2. [Quorum Queues In-Depth](#2-quorum-queues-in-depth)
3. [Streams](#3-streams)
4. [Classic Queues v2](#4-classic-queues-v2)
5. [Publisher Confirms](#5-publisher-confirms)
6. [Consumer Prefetch (QoS)](#6-consumer-prefetch-qos)
7. [Dead Letter Exchanges (DLX)](#7-dead-letter-exchanges-dlx)
8. [TTL (Time-To-Live)](#8-ttl-time-to-live)
9. [Flow Control & Back-Pressure](#9-flow-control--back-pressure)
10. [Connections & Channels](#10-connections--channels)
11. [Heartbeats & TCP Tuning](#11-heartbeats--tcp-tuning)
12. [Memory Management](#12-memory-management)
13. [Clustering](#13-clustering)
14. [Network Partitions](#14-network-partitions)
15. [Monitoring](#15-monitoring)
16. [Erlang VM Runtime Tuning](#16-erlang-vm-runtime-tuning)
17. [Production Checklist](#17-production-checklist)
18. [Reliability Patterns](#18-reliability-patterns)
19. [Networking & Port Reference](#19-networking--port-reference)

---

## 1. Queue Types Comparison

| Feature | Classic v2 | Quorum | Stream |
|---|---|---|---|
| Replication | No | Raft consensus | Raft consensus |
| Durability | Optional (deprecated transient) | Always durable | Always durable |
| Message ordering | FIFO | FIFO (redelivery at back unless delivery-limit set) | Append-only log |
| Non-destructive read | No | No | Yes |
| Dead letter exchanges | Yes (at-most-once) | Yes (at-most-once or at-least-once) | No |
| Message TTL | Yes | Yes (+16 bytes/msg overhead) | No (use retention) |
| Message priority | Yes (up to 255) | Yes (2-tier: normal 0-4, high >4) | No |
| Exclusive queues | Yes | No | No |
| Global QoS | Deprecated | No (channel error) | No (channel error) |
| Consumer prefetch (per-consumer) | Yes | Yes | Yes (credit-based) |
| Max backlog recommended | Moderate | < 5M messages | Unlimited (disk-based) |
| Fan-out | Poor | Poor | Excellent |
| Replay / time-travel | No | No | Yes |
| Single Active Consumer | Yes | Yes | Yes (3.11+) |

**When to use what:**
- **Classic v2**: Temporary queues, low-importance data, single-node setups, exclusive queues
- **Quorum**: Long-lived critical queues, order processing, anything requiring HA with strong safety
- **Stream**: Large fan-out, replay, high-throughput ingestion, large backlogs (millions of messages)

---

## 2. Quorum Queues In-Depth

### 2.1 Declaration

```java
Map<String, Object> args = new HashMap<>();
args.put("x-queue-type", "quorum");
args.put("x-quorum-initial-group-size", 3);
channel.queueDeclare("orders", true, false, false, args);
```

### 2.2 All x-arguments

| Argument | Type | Default | Notes |
|---|---|---|---|
| `x-queue-type` | string | `"classic"` | Must be `"quorum"`. Cannot be set via policy |
| `x-quorum-initial-group-size` | int | 3 (`rabbit.quorum_cluster_size`) | Must be > 0 and <= cluster size |
| `x-quorum-target-group-size` | int | none | Target for CMR reconciliation |
| `x-queue-leader-locator` | string | `"client-local"` | `"client-local"` or `"balanced"` |
| `x-dead-letter-exchange` | string | none | DLX target exchange |
| `x-dead-letter-routing-key` | string | none | Override routing key for DLX |
| `x-dead-letter-strategy` | string | `"at-most-once"` | `"at-most-once"` or `"at-least-once"` |
| `x-max-length` | int | none | Max messages in queue |
| `x-max-length-bytes` | int | none | Max total bytes in queue |
| `x-overflow` | string | `"drop-head"` | `"drop-head"` or `"reject-publish"` |
| `x-message-ttl` | int (ms) | none | Per-queue message TTL |
| `x-expires` | int (ms) | none | Queue auto-delete after idle period |
| `x-delivery-limit` | int | 20 (since RMQ 4.0) | -1 to disable. Poison message protection |

### 2.3 Policy Keys

| Policy Key | Type | Notes |
|---|---|---|
| `max-length` | int | Queue message limit |
| `max-length-bytes` | int | Queue byte limit |
| `overflow` | string | `"drop-head"` or `"reject-publish"` |
| `expires` | int (ms) | Queue TTL |
| `dead-letter-exchange` | string | DLX target |
| `dead-letter-routing-key` | string | DLX routing key |
| `dead-letter-strategy` | string | `"at-most-once"` or `"at-least-once"` |
| `delivery-limit` | int | Redelivery limit |
| `target-group-size` | int | CMR target |
| `queue-leader-locator` | string | `"client-local"` or `"balanced"` |

### 2.4 Server Configuration (rabbitmq.conf / advanced.config)

```ini
# rabbitmq.conf
quorum_queue.initial_cluster_size = 3
quorum_queue.commands_soft_limit = 32
```

| Parameter | Default | Purpose |
|---|---|---|
| `rabbit.quorum_cluster_size` | 3 | Default replication factor |
| `rabbit.quorum_commands_soft_limit` | 32 | Flow control threshold for unconfirmed messages |
| `raft.wal_max_size_bytes` | 512000000 (512 MiB) | WAL flush trigger |
| `raft.segment_max_entries` | 4096 | Entries per Raft log segment file |
| `rabbit.dead_letter_worker_consumer_prefetch` | 32 | Internal DLX consumer prefetch |

### 2.5 Continuous Membership Reconciliation (CMR)

```ini
quorum_queue.continuous_membership_reconciliation.enabled = true
quorum_queue.continuous_membership_reconciliation.target_group_size = 3
quorum_queue.continuous_membership_reconciliation.auto_remove = false
quorum_queue.continuous_membership_reconciliation.interval = 3600000
quorum_queue.continuous_membership_reconciliation.trigger_interval = 10000
```

CMR automatically adds/removes replicas when cluster membership changes. Triggers on node addition/removal and policy changes. Does NOT trigger on single node failures or rolling upgrades.

### 2.6 Fault Tolerance Matrix

| Cluster Size | Tolerable Failures | Quorum Required |
|---|---|---|
| 3 | 1 | 2 |
| 5 | 2 | 3 |
| 7 | 3 | 4 |
| 9 | 4 | 5 |

Rule: `quorum = (N/2) + 1`. Never use 2-node clusters. No benefit beyond 7 replicas.

### 2.7 CLI Commands

```bash
# Member management
rabbitmq-queues add_member [-p <vhost>] <queue-name> <node>
rabbitmq-queues delete_member [-p <vhost>] <queue-name> <node>
rabbitmq-queues grow <node> <all|even> [--vhost-pattern <pat>] [--queue-pattern <pat>]
rabbitmq-queues shrink <node> [--errors-only]

# Rebalance leaders across cluster
rabbitmq-queues rebalance quorum
rabbitmq-queues rebalance quorum --queue-pattern "orders.*"

# Set policy (apply only to quorum queues)
rabbitmqctl set_policy ha-orders "^orders\." \
  '{"dead-letter-exchange":"dlx","delivery-limit":5}' \
  --priority 1 --apply-to quorum_queues
```

### 2.8 Memory Footprint

- **Per message overhead**: minimum 32 bytes metadata (more with TTL: +16 bytes)
- **Rule of thumb**: ~1 MB per 30,000 messages regardless of message size
- **WAL memory**: Can reach `raft.wal_max_size_bytes` (default 512 MiB)
- **Recommendation**: Allocate 3-4x WAL file size limit in total node memory

### 2.9 Performance Tuning

**Small messages (< 8 KB):**
```ini
# advanced.config
raft.segment_max_entries = 32768   % up to 65535; reduces segment file count
```

**Large messages (100s KB to MiB):**
```ini
raft.segment_max_entries = 128     % keeps segment files manageable
```

**Linux readahead tuning:**
```bash
sudo blockdev --getra /dev/sda      # check current value
sudo blockdev --setra 4096 /dev/sda  # optimize for small messages
```

### 2.10 At-Least-Once Dead Lettering (Quorum-Only)

Requirements (ALL must be met):
1. `dead-letter-strategy` = `"at-least-once"`
2. `overflow` = `"reject-publish"` (NOT `"drop-head"`)
3. `dead-letter-exchange` configured
4. `stream_queue` feature flag enabled

Caveats:
- Internal DLX consumer is co-located on queue leader
- Dead-lettered messages kept in memory (prefetch: 32)
- Retries if target exchange/queue unavailable (risk of duplicates)
- Long-term target unavailability causes source queue bloat

### 2.11 Unsupported Features

- Non-durable queues (always durable)
- Exclusive queues
- Server-named queues
- Global QoS (returns channel error)
- `x-overflow: reject-publish-dlx`
- Queue lease renewal on redeclaration

### 2.12 Redelivery Behavior

- **Without delivery-limit**: Messages returned to BACK of queue (prevents Raft log bloat)
- **With delivery-limit**: Messages returned near HEAD (original behavior for limit enforcement)
- Poison messages exceeding `delivery-limit` are dropped or dead-lettered

---

## 3. Streams

### 3.1 Declaration

```java
Map<String, Object> args = new HashMap<>();
args.put("x-queue-type", "stream");
args.put("x-max-length-bytes", 5_000_000_000L); // 5 GB
args.put("x-max-age", "7D");
channel.queueDeclare("events", true, false, false, args);
```

### 3.2 All x-arguments

| Argument | Type | Default | Notes |
|---|---|---|---|
| `x-queue-type` | string | `"classic"` | Must be `"stream"` |
| `x-max-length-bytes` | long | not set | Max stream size on disk |
| `x-max-age` | string | not set | Retention: `"7D"`, `"1h"`, `"30m"`, etc. Units: Y/M/D/h/m/s |
| `x-stream-max-segment-size-bytes` | int | 500000000 (500 MB) | Fixed at declaration; policy changes ignored for existing streams |
| `x-stream-filter-size-bytes` | int | 16 | Bloom filter size (range 16-255 bytes) |
| `x-initial-cluster-size` | int | cluster size | Number of initial replicas |
| `x-queue-leader-locator` | string | `"client-local"` | `"client-local"` or `"balanced"` |

### 3.3 Consumer Offset Specification (`x-stream-offset`)

| Value | Behavior |
|---|---|
| `"first"` | Earliest available message |
| `"last"` | Most recent chunk |
| `"next"` | Next message after subscription (default) |
| Numeric offset | Specific position (clamped if out of range) |
| Timestamp (POSIX seconds) | Attach at chunk boundary >= timestamp |
| Interval string (`"7D"`) | Relative time offset |

### 3.4 Producer Deduplication

- Producer name must be unique per stream
- Publishing ID must be strictly increasing (gaps OK, no restart needed)
- Broker filters messages with ID <= current; sends confirm regardless
- New producers query broker for last publishing ID to resume

### 3.5 CLI Commands

```bash
rabbitmq-streams add_replica [-p <vhost>] <stream-name> <node>
rabbitmq-streams delete_replica [-p <vhost>] <stream-name> <node>
rabbitmq-streams stream_status [-p <vhost>] <stream-name>
rabbitmq-streams restart_stream [-p <vhost>] <stream-name>

# Super streams (partitioned, RabbitMQ 3.11+)
rabbitmq-streams add_super_stream <name> --partitions <count>
```

### 3.6 Key Differences from Queues

- Always durable, never exclusive
- No TTL, no message priority, no dead letter exchanges
- Non-destructive reads (append-only log)
- Disk-based with minimal RAM usage
- Heavy kernel page cache usage (important for containers)
- Consumer acks function as credit mechanism, not message deletion
- AMQP 0.9.1 to 1.0 conversion drops complex header values (arrays/tables)

### 3.7 Single Active Consumer (3.11+)

- Only one consumer active per consumer group
- Others idle as standby
- Automatic failover on consumer failure
- Ensures ordered processing

---

## 4. Classic Queues v2

### 4.1 Overview

CQv2 is the default since RabbitMQ 4.0. Automatic v1-to-v2 conversion on startup.

### 4.2 Storage Architecture

- **Per-queue message store**: stores messages > 4096 bytes (embedding threshold)
- **Segment file-based index**: loads messages from disk only when needed
- **File handles**: up to 6 per queue (4 index + 1 store + 1 flush)
- **Shared message store**: 1 persistent + 1 transient per vhost

### 4.3 Memory Configuration

```ini
classic_queue_store_v2_max_cache_size = 1048576  # 1 MB total (512KB write buffer + 512KB cache)
```

- Max 2048 messages kept in memory
- Messages > 4096 bytes not loaded prematurely
- Idle queues reduce memory automatically
- Direct publisher-to-consumer delivery skips disk if consumer acks before flush

### 4.4 v1 to v2 Migration Benchmarks

| Scenario | Time |
|---|---|
| 1,000 queues x 1,000 msgs (100 B) | ~2 seconds |
| 1 queue x 1M msgs (100 B) | ~9 seconds |
| 1 queue x 1M msgs (5,000 B) | ~3 seconds |

### 4.5 Lazy Queue Mode (Deprecated)

`x-queue-mode = lazy` is **ignored since RabbitMQ 3.12**. CQv2 inherently provides similar behavior: messages written to disk with brief memory buffering, small subset kept in memory for fast delivery.

---

## 5. Publisher Confirms

### 5.1 Enabling

```java
channel.confirmSelect(); // Puts channel in confirm mode
```

- Channel cannot be made transactional after `confirm.select`
- Transactional channels cannot enter confirm mode
- Message counting starts at 1 on first `confirm.select`

### 5.2 Confirmation Mechanics

| Scenario | When `basic.ack` is Sent |
|---|---|
| Unroutable message | After exchange verifies no matching queue |
| Mandatory + unroutable | `basic.return` sent BEFORE `basic.ack` |
| Routable to classic queue | After accepted by all target queues |
| Persistent + durable queue | After persisting to disk |
| Quorum queue | After quorum replicas confirm to leader |

### 5.3 Negative Acknowledgements

`basic.nack` sent only when internal Erlang process error occurs for a queue. No message is ever both ack'd and nack'd.

### 5.4 Ordering Guarantees

- Broker acks messages in **same order** as published (per channel)
- But acks arrive **asynchronously** -- order of arrival may differ
- **Do not depend on ack arrival order**

### 5.5 Batching & Performance

- Message store persists to disk in batches (interval: a few hundred milliseconds)
- Transactions decrease throughput by **factor of 250** vs confirms
- **Recommendation**: Process acks asynchronously (stream) or publish in batches and wait

### 5.6 Delivery Tag

- 64-bit long, scoped per channel
- Max value: 9223372036854775807 (overflow practically impossible)

### 5.7 Critical Safety Note

Without publisher confirms, a node can lose persistent messages if it fails before writing to disk. The publisher receives NO failure notification.

---

## 6. Consumer Prefetch (QoS)

### 6.1 Configuration

```java
channel.basicQos(10);          // Per-consumer limit: 10 unacked messages
channel.basicQos(10, false);   // Same as above (explicit per-consumer)
channel.basicQos(15, true);    // Global channel-level limit (shared across all consumers)
```

### 6.2 Parameters

| Setting | Default | Notes |
|---|---|---|
| `prefetchCount` | 0 (unlimited) | 0 = infinite unacked messages allowed |
| `global` flag | false | false = per-consumer, true = per-channel (slower due to coordination) |
| `default_consumer_prefetch` | `{false, 250}` | Server default in advanced.config: `{global_flag, count}` |

### 6.3 Performance Implications

- **Prefetch 0 (unlimited)**: Maximum throughput but risk of memory exhaustion
- **Prefetch 1**: Maximum fairness but minimum throughput
- **Prefetch 10-50**: Good balance for most workloads
- **Prefetch 100-300**: High-throughput scenarios
- **Global (channel-level)**: Slower than per-consumer due to cross-queue coordination overhead
- Quorum queues: Only per-consumer prefetch supported (global returns channel error)

### 6.4 RabbitMQ Default

```erlang
% advanced.config
{rabbit, [{default_consumer_prefetch, {false, 250}}]}
```

The default 250 per consumer is applied when client does not explicitly set QoS.

---

## 7. Dead Letter Exchanges (DLX)

### 7.1 Dead-Lettering Triggers

1. `basic.reject` or `basic.nack` with `requeue=false`
2. Message TTL expiration
3. Queue length limit exceeded (`x-max-length` / `x-max-length-bytes`)
4. Delivery limit exceeded (quorum queues only, `x-delivery-limit`)

### 7.2 Configuration (Policy -- Recommended)

```bash
rabbitmqctl set_policy dlx-policy ".*" \
  '{"dead-letter-exchange":"my-dlx","dead-letter-routing-key":"dlx-routing"}' \
  --apply-to queues
```

### 7.3 Configuration (Queue Arguments -- Not Recommended)

```java
Map<String, Object> args = new HashMap<>();
args.put("x-dead-letter-exchange", "my-dlx");
args.put("x-dead-letter-routing-key", "dlx-routing");
channel.queueDeclare("my-queue", true, false, false, args);
```

**Warning**: Hardcoded x-arguments cannot be updated without redeploying applications.

### 7.4 Routing Rules

- If `dead-letter-routing-key` set: uses that key
- Otherwise: uses original message routing keys (including CC headers)
- CC header removed if routing key overridden; BCC always removed

### 7.5 Dead Letter Reasons in Headers

| Reason | When |
|---|---|
| `rejected` | Consumer rejected with requeue=false |
| `expired` | Message or queue TTL |
| `maxlen` | Queue length limit exceeded |
| `delivery_limit` | Quorum queue delivery limit exceeded |

Headers: `x-death` (AMQP 0.9.1) or `x-opt-deaths` (AMQP 1.0) with {Queue, Reason} compression.

### 7.6 Cycle Detection

RabbitMQ detects cycles and **drops the message** if there was no rejection in the entire cycle.

### 7.7 Safety Guarantees

| Strategy | Queue Type | Behavior |
|---|---|---|
| `at-most-once` (default) | All | Message removed from source BEFORE confirm from DLX target |
| `at-least-once` | Quorum only | Internal publisher confirms; retries on failure; risk of duplicates |

### 7.8 Permissions Required

At queue declaration time, user must have:
- Configure permissions on declared queue
- Read permissions on source queue
- Write permissions on dead letter exchange

---

## 8. TTL (Time-To-Live)

### 8.1 Per-Queue Message TTL

```bash
# Via policy (recommended)
rabbitmqctl set_policy TTL ".*" '{"message-ttl":60000}' --apply-to queues
```

```java
// Via queue argument
Map<String, Object> args = new HashMap<>();
args.put("x-message-ttl", 60000); // 60 seconds in milliseconds
channel.queueDeclare("my-queue", false, false, false, args);
```

### 8.2 Per-Message TTL

```java
AMQP.BasicProperties properties = new AMQP.BasicProperties.Builder()
    .expiration("60000") // String, milliseconds
    .build();
channel.basicPublish("", "my-queue", properties, body);
```

### 8.3 Rules

- When both per-queue and per-message TTL exist: **lower value wins**
- TTL of 0: message expires immediately unless delivered directly to consumer
- Must be non-negative integer
- All TTL values in **milliseconds**
- Requeued messages retain original expiry time

### 8.4 Queue TTL (x-expires)

Auto-delete unused queues:

```bash
# Via policy (30 minutes)
rabbitmqctl set_policy expiry ".*" '{"expires":1800000}' --apply-to queues
```

```java
args.put("x-expires", 1800000); // Must be positive (> 0, unlike message TTL)
```

- "Unused" = no consumers, not recently redeclared, no basic.get
- Only applies to transient classic queues (not streams)

### 8.5 Critical Caveats

- **Classic queues**: Expired messages discarded only when they reach HEAD of queue
- Expired messages can pile behind non-expired ones, consuming memory/disk
- **Quorum queues**: Dead-letter expired messages at head of queue
- Retroactive TTL policy changes: existing messages expire only when reaching head
- **Recommendation**: Have consumers online to ensure timely expiry

---

## 9. Flow Control & Back-Pressure

### 9.1 Mechanism

Flow control is automatic back-pressure on publishing connections. No configuration needed.

### 9.2 Behavior

- Connection enters `flow` state (visible in `rabbitmqctl`, management UI, HTTP API)
- Connection blocks/unblocks several times per second
- Propagates from queues -> channels -> connections
- **Consumers are NOT affected** by publisher flow control
- From client perspective: transparent; only slower throughput

### 9.3 Resource Alarms (Triggers for Connection Blocking)

| Alarm | Trigger | Effect |
|---|---|---|
| Memory | `vm_memory_high_watermark` exceeded | Block all publishers cluster-wide |
| Disk | `disk_free_limit` exceeded | Block all publishers cluster-wide |

### 9.4 Best Practice

Use **separate connections** for publishers and consumers to isolate flow control impact.

---

## 10. Connections & Channels

### 10.1 Connection Resource Usage

Each connection consumes:
- Memory (TCP buffers)
- 1 file handle on the node
- Erlang processes

### 10.2 Connection Configuration

| Parameter | Default | Notes |
|---|---|---|
| `handshake_timeout` | 10000 ms | Connection handshake timeout |
| `ssl_handshake_timeout` | 10000 ms | TLS handshake timeout |
| `collect_statistics_interval` | 5000 ms | Reduce to 30000-60000 for large connection counts |
| `reverse_dns_lookups` | false | Enable for debugging |

### 10.3 Channel Configuration

| Parameter | Default | Notes |
|---|---|---|
| `channel_max` | 2048 | Max channels per connection (negotiated) |
| `channel_max_per_node` | none | Max channels across all connections on node |

**Guidelines**:
- Most apps need single-digit channels per connection
- Values above 200 rarely necessary
- Each channel = several Erlang processes
- Close unused channels explicitly

### 10.4 Connection Churn Warning

> Rates consistently above 100 connections/second likely indicate suboptimal connection management.

### 10.5 CLI Commands

```bash
rabbitmqctl list_connections name peer_host peer_port state channels
rabbitmqctl list_channels name connection consumer_count messages_unacknowledged prefetch_count

# Suspend/resume listeners (graceful maintenance)
rabbitmqctl suspend_listeners
rabbitmqctl resume_listeners
```

### 10.6 Statistics Collection Tuning

```ini
# For nodes with many connections (>10K), reduce overhead:
collect_statistics_interval = 60000
```

---

## 11. Heartbeats & TCP Tuning

### 11.1 Heartbeat Configuration

| Parameter | Default | Notes |
|---|---|---|
| Server suggested timeout | 60 seconds | |
| Recommended range | 5-20 seconds | Below 5s = high false-positive risk |
| Frame interval | `timeout / 2` | |
| Detection | 2 consecutive missed frames | Then TCP connection closed |

**Negotiation**: If either peer sends 0, greater value used. Otherwise, smaller value used.

### 11.2 TCP Keepalive (OS-Level Alternative)

```bash
# Detect dead connections in ~70 seconds
sysctl -w net.ipv4.tcp_keepalive_time=30
sysctl -w net.ipv4.tcp_keepalive_intvl=10
sysctl -w net.ipv4.tcp_keepalive_probes=4
```

Enable in RabbitMQ:
```ini
tcp_listen_options.keepalive = true
```

When using TCP keepalives: set heartbeat timeout to 8-20 seconds.

### 11.3 TCP Buffer Sizing

**RabbitMQ 4.1+**: Auto-tuning based on message rates/sizes.

**Manual (throughput-optimized):**
```ini
tcp_listen_options.sndbuf = 196608
tcp_listen_options.recbuf = 196608
```

**Manual (many connections):**
```ini
tcp_listen_options.sndbuf = 32768
tcp_listen_options.recbuf = 32768
```

### 11.4 TCP Socket Options

| Parameter | Default | Recommendation |
|---|---|---|
| `tcp_listen_options.nodelay` | true | Keep true (disables Nagle) |
| `tcp_listen_options.backlog` | 128 | Increase to 4096 for high connection churn |
| `tcp_listen_options.keepalive` | false | Enable in production |
| `tcp_listen_options.linger` | `{true, 0}` | Default is fine |

### 11.5 OS Kernel Tuning

```bash
# Connection backlog
sysctl -w net.core.somaxconn=4096
sysctl -w net.ipv4.tcp_max_syn_backlog=4096

# TIME_WAIT optimization
sysctl -w net.ipv4.tcp_fin_timeout=30
sysctl -w net.ipv4.tcp_tw_reuse=1   # Only safe without NAT
```

---

## 12. Memory Management

### 12.1 Watermark Configuration

```ini
# Relative (default, not recommended for containers)
vm_memory_high_watermark.relative = 0.6

# Absolute (recommended for containers)
vm_memory_high_watermark.absolute = 4Gi
```

| Parameter | Default | Notes |
|---|---|---|
| `vm_memory_high_watermark.relative` | 0.6 (60%) | Range: 0.4-0.7 recommended |
| `vm_memory_high_watermark.absolute` | none | Supports: GB, MB, Gi, Mi, Ti |
| `total_memory_available_override_value` | auto-detected | Manual override for undetected platforms |

### 12.2 Behavior

- Exceeding watermark triggers **resource alarm** -> blocks ALL publishers cluster-wide
- Does NOT prevent node from using more memory (only throttles publishers)
- Alarm clears when memory drops below threshold
- Setting to 0 blocks all publishing

### 12.3 Runtime Commands

```bash
rabbitmqctl set_vm_memory_high_watermark 0.7
rabbitmqctl set_vm_memory_high_watermark absolute "4G"
rabbitmq-diagnostics memory_breakdown --unit "MB"
rabbitmq-diagnostics status
```

### 12.4 Recommended Ranges

- **0.4-0.7**: Safe range for most workloads
- **Above 0.7**: Requires solid monitoring; OS needs >= 30% for page cache
- **Containers**: Always use absolute values
- **Minimum reserve**: 256 MiB available at all times
- **Quorum queues**: Additional reserves needed (WAL memory)

---

## 13. Clustering

### 13.1 Cluster Formation Methods

- Config file with node listings
- DNS-based discovery
- AWS EC2 instance discovery (plugin)
- Kubernetes discovery (plugin)
- Consul-based discovery (plugin)
- etcd-based discovery (plugin)
- Manual: `rabbitmqctl join_cluster rabbit@node1`

### 13.2 Required Ports

| Port | Purpose |
|---|---|
| 4369 | epmd (Erlang Port Mapper Daemon) |
| 5672 | AMQP 0-9-1 / AMQP 1.0 |
| 5671 | AMQP + TLS |
| 6000-6500 | Stream replication |
| 15672 | Management UI / HTTP API |
| 15692 | Prometheus metrics |
| 25672 | Inter-node communication (AMQP port + 20000) |
| 35672-35682 | CLI tools (distribution port + 10000..10010) |

### 13.3 Erlang Cookie

- Must be identical on all nodes
- Alphanumeric, up to 255 characters
- File permissions: mode 600
- Location: `/var/lib/rabbitmq/.erlang.cookie` (Linux)

```bash
# Diagnostic
rabbitmq-diagnostics erlang_cookie_sources
```

### 13.4 Node Naming

```bash
# Short name (default)
RABBITMQ_NODENAME=rabbit@myhost

# Long name (FQDN)
RABBITMQ_USE_LONGNAME=true
RABBITMQ_NODENAME=rabbit@node1.messaging.svc.local
```

### 13.5 Node Count

- **2-node clusters: HIGHLY DISCOURAGED** (cannot form quorum on partition)
- **3 nodes**: Minimum for production (tolerates 1 failure)
- **5 nodes**: Tolerates 2 failures
- **Odd numbers always** for partition recovery

### 13.6 Leader Placement Strategy

```ini
# In rabbitmq.conf
queue_leader_locator = balanced   # or client-local (default)
```

- `client-local`: Leader on declaring client's node
- `balanced`: Distributes leaders evenly (random if >1000 queues)

### 13.7 Peer Sync on Restart

```ini
mnesia_table_loading_retry_timeout = 60000   # ms, default 30000
mnesia_table_loading_retry_limit = 15        # default 10
```

Total sync window = timeout x limit (default: ~5 minutes).

### 13.8 CLI Commands

```bash
# Join cluster
rabbitmqctl stop_app
rabbitmqctl join_cluster rabbit@node1
rabbitmqctl start_app

# Remove node (online)
rabbitmqctl forget_cluster_node rabbit@deadnode

# Remove node (offline)
rabbitmqctl forget_cluster_node --offline rabbit@deadnode

# Reset node (DESTRUCTIVE: deletes all data)
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl start_app

# Force boot (when last node is permanently gone)
rabbitmqctl force_boot

# Grow quorum queues to new node
rabbitmq-queues grow rabbit@newnode all
```

### 13.9 Data Replication Model

- **Metadata** (exchanges, bindings, users, vhosts, policies): replicated to ALL nodes
- **Classic queues**: Single node (no replication)
- **Quorum queues**: Raft-replicated across configured members
- **Streams**: Replicated across configured members

---

## 14. Network Partitions

### 14.1 Detection

```bash
rabbitmq-diagnostics cluster_status   # Shows partitions
```

Logs: `** ERROR ** mnesia_event got {inconsistent_database, running_partitioned_network, ...}`
HTTP API: `GET /api/nodes` -> `partitions` field

Detection delay: ~60 seconds (net_ticktime).

### 14.2 Handling Strategies

```ini
# rabbitmq.conf
cluster_partition_handling = pause_minority
```

| Strategy | Behavior | Best For |
|---|---|---|
| `ignore` (default) | No action; split-brain risk | Single datacenter, reliable network |
| `pause_minority` | Minority nodes pause | Multi-rack/zone (3+ nodes, odd count) |
| `autoheal` | Winning partition restarts losers | Consistency-flexible, availability-first |
| `pause_if_all_down` | Pause if listed nodes unreachable | Selective rack prioritization |

### 14.3 pause_if_all_down Configuration

```ini
cluster_partition_handling.pause_if_all_down.nodes.1 = rabbit@node1
cluster_partition_handling.pause_if_all_down.nodes.2 = rabbit@node2
cluster_partition_handling.pause_if_all_down.recover = autoheal
```

### 14.4 Manual Recovery

1. Identify trusted partition (authoritative state)
2. Stop all nodes in non-trusted partitions
3. Restart non-trusted nodes (they sync from trusted)
4. Restart trusted nodes to clear warnings

### 14.5 Quorum Queue Behavior During Partition

- Majority side: Elects new leader, continues normally
- Minority side: Halts progress (no message accept/deliver)
- Permanent quorum loss (2/3 down): Queue permanently unavailable; force delete + recreate required

---

## 15. Monitoring

### 15.1 Prometheus Setup

```bash
rabbitmq-plugins enable rabbitmq_prometheus
# Metrics at: http://hostname:15692/metrics
# Scrape interval: 15-30 seconds (production)
```

### 15.2 Health Check Stages (Progressive)

```bash
# Stage 1: Is the Erlang VM running?
rabbitmq-diagnostics -q ping

# Stage 2: System information
rabbitmq-diagnostics -q status

# Stage 3: App running + no alarms?
rabbitmq-diagnostics -q check_running
rabbitmq-diagnostics -q check_local_alarms
rabbitmq-diagnostics -q alarms

# Stage 4: Listeners accessible?
rabbitmq-diagnostics -q listeners
rabbitmq-diagnostics -q check_port_connectivity

# Stage 5: Virtual hosts OK?
rabbitmq-diagnostics -q check_virtual_hosts
```

### 15.3 Key HTTP API Endpoints

| Endpoint | Key Metrics |
|---|---|
| `GET /api/overview` | cluster_name, object_totals.*, queue_totals.*, message_stats.* |
| `GET /api/nodes/{node}` | mem_used, mem_limit, mem_alarm, disk_free_limit, disk_free_alarm, fd_total, fd_used, proc_total, proc_used, run_queue, gc_num, gc_bytes_reclaimed |
| `GET /api/queues/{vhost}/{queue}` | memory, messages, messages_ready, messages_unacknowledged, message_stats.* |
| `GET /api/nodes/{node}/memory` | Detailed memory breakdown |

### 15.4 Critical Metrics to Alert On

| Metric | Alert Condition |
|---|---|
| `mem_alarm` | true |
| `disk_free_alarm` | true |
| `fd_used / fd_total` | > 80% |
| `messages_unacknowledged` | Growing continuously |
| `run_queue` | Consistently > 0 (CPU saturation) |
| Connection churn | > 100/second |

### 15.5 Memory Breakdown

```bash
rabbitmq-diagnostics -q memory_breakdown --unit "MB"
```

### 15.6 Interactive Observer

```bash
rabbitmq-diagnostics observer   # ncurses TUI, like htop for RabbitMQ
```

### 15.7 Kubernetes Readiness Probe

Best practice (from RabbitMQ Operator): TCP port check on AMQP port. Do NOT use liveness probes.

### 15.8 OS-Level Metrics to Collect

- CPU: user, system, iowait, idle
- Memory: used, buffered, cached, free
- Kernel page cache (critical for streams)
- Disk I/O: frequency, latency distribution
- Free disk space on data directory
- File descriptors: `beam.smp` process vs system limit
- TCP states: ESTABLISHED, CLOSE_WAIT, TIME_WAIT
- Network throughput and latency (inter-node and client)

---

## 16. Erlang VM Runtime Tuning

### 16.1 Scheduler Configuration

```bash
# Set via environment variable (recommended)
RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+S 4:4"
```

| Flag | Default | Notes |
|---|---|---|
| `+S N:N` | 1 per CPU core | Number of schedulers. Erlang 23+ respects container CPU quotas |
| `+sbwt none` | `none` | Disable speculative busy waiting (saves CPU) |
| `+sbwtdcpu none` | `none` | Disable dirty CPU scheduler busy waiting |
| `+sbwtdio none` | `none` | Disable dirty I/O scheduler busy waiting |
| `+stbt db` | `db` | Scheduler-to-CPU binding. Options: db, tnnps, nnts, nnps, ts, ps, s, ns |

### 16.2 Memory Allocator

Default: `+MBas ageffcbf +MHas ageffcbf +MBlmbcs 512 +MHlmbcs 512 +MMmcs 30`

**Super carriers (pre-allocate memory):**
```bash
RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+MMscs 1024 +MMscrpm true"
# Allocates 1 GiB at startup; +MMscrpm true = reserve physical memory immediately
```

**For large messages:**
```bash
RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+MBlmbcs 2048"  # 2 MiB binary carrier limit
# or +MBlmbcs 8192 for very large messages
```

### 16.3 Process & Atom Limits

| Parameter | Default | When to Increase |
|---|---|---|
| `+P` / `RABBITMQ_MAX_NUMBER_OF_PROCESSES` | ~1,000,000 | High-concurrency workloads |
| `+t` / `RABBITMQ_MAX_NUMBER_OF_ATOMS` | 5,000,000 | High quorum queue churn |

### 16.4 Inter-node Distribution Buffer

```bash
RABBITMQ_DISTRIBUTION_BUFFER_SIZE=192000  # kilobytes (default: 128000 = 128 MB)
# Minimum recommended: 64 MB. Increase for heavy inter-node traffic.
```

Warning log when approaching capacity: `busy_dist_port`

### 16.5 Diagnostics

```bash
rabbitmq-diagnostics runtime_thread_stats   # Thread activity breakdown
```

### 16.6 Crash Dumps

```bash
ERL_CRASH_DUMP_BYTES=0   # Disable crash dump generation
```

---

## 17. Production Checklist

### 17.1 Hardware Minimums

| Resource | Minimum | Notes |
|---|---|---|
| CPU cores | 4 | RabbitMQ NOT designed for single-core |
| RAM | 4 GiB | |
| Storage | SSD/NVMe preferred | No distributed filesystems |
| Network | Calculate: `msg_rate * msg_size * 1.1 * 8` | Example: 20K msg/s x 6KB = 1 Gbps |

### 17.2 File Descriptors

```bash
# Production minimum: 50,000
# Formula: (95th percentile connections x 2) + queue count
# Recommended: up to 500K (minimal hardware impact)
ulimit -n 500000
```

### 17.3 Memory Settings

```ini
vm_memory_high_watermark.relative = 0.6    # Range: 0.4-0.7
# Above 0.7 requires solid monitoring
# OS must retain >= 30% memory for page cache
```

### 17.4 Disk Settings

```ini
disk_free_limit.absolute = 4Gi   # At least equal to memory watermark
# Rule: when in doubt, overprovision
```

### 17.5 Security Checklist

- [ ] Delete default `guest` account
- [ ] Create per-application users with strong passwords
- [ ] Enable TLS for client connections
- [ ] Enable TLS for inter-node communication
- [ ] Restrict Erlang cookie file permissions (mode 600)
- [ ] Firewall: only expose client ports to app hosts
- [ ] Firewall: restrict inter-node/CLI ports to RabbitMQ hosts

```ini
# Disable anonymous login
auth_mechanisms.1 = PLAIN
auth_mechanisms.2 = AMQPLAIN
anonymous_login_user = none
```

### 17.6 Connection Management Rules

- Use **long-lived connections** (protocol design assumption)
- Separate publisher and consumer connections (flow control isolation)
- Heartbeats: > 5 seconds recommended
- Avoid short-lived single-operation connections
- Implement connection pooling if long-lived not possible
- Use client library auto-recovery (Java, .NET, Ruby)

### 17.7 Channel Rules

- Keep channels long-lived
- Single-digit channels per connection for most apps
- Close unused channels explicitly
- Avoid polling (`basic.get`); use push-based consumption

### 17.8 Cluster Sizing

- 3 nodes minimum for production
- Odd numbers for partition recovery
- `pause_minority` strategy with odd node counts
- Queue replication: more than half but not all cluster nodes
- NTP on all nodes (prevents stat calculation errors)
- Consider independent clusters instead of >10 nodes

### 17.9 Limits & Quotas

```bash
# Per-vhost limits
rabbitmqctl set_vhost_limits -p my_vhost '{"max-connections": 1000, "max-queues": 500}'

# Per-user limits
rabbitmqctl set_user_limits my_user '{"max-connections": 100, "max-channels": 50}'
```

### 17.10 Virtual Host Strategy

- Single-tenant: default vhost `/` is fine
- Multi-tenant: separate vhost per tenant/environment
- Naming: `project1_development`, `project1_production`

---

## 18. Reliability Patterns

### 18.1 At-Least-Once Delivery

Requirements:
1. Publisher confirms enabled
2. Durable queue declared
3. Messages published as persistent
4. Consumer manual acknowledgements (no auto-ack)
5. For HA: quorum queue or stream

Risk: Message duplication on publisher retry after timeout. Consumers must be **idempotent**.

### 18.2 At-Most-Once Delivery

Default without confirms/acks. Messages may be lost but never duplicated.

### 18.3 Exactly-Once Semantics

Not natively supported. Implement via idempotent consumers + deduplication logic.

### 18.4 Heartbeat-Based Failure Detection

AMQP 0-9-1 heartbeats detect dead connections much faster than OS TCP detection (~11 minutes default).

### 18.5 Redelivered Flag

`redelivered = true` indicates message was previously delivered (at least once). Consumers can use this for conditional deduplication.

### 18.6 Federation & Shovel

Both use confirms/acks by default, support multiple URIs for failover, and auto-recover from network failures.

---

## 19. Networking & Port Reference

### 19.1 All Default Ports

| Port | Protocol | TLS Port |
|---|---|---|
| 5672 | AMQP 0-9-1 / AMQP 1.0 | 5671 |
| 5552 | RabbitMQ Streams | 5551 |
| 15672 | Management UI / HTTP API | 15671 |
| 15692 | Prometheus metrics | 15691 |
| 61613 | STOMP | 61614 |
| 1883 | MQTT | 8883 |
| 15674 | STOMP-over-WebSockets | -- |
| 15675 | MQTT-over-WebSockets | -- |
| 4369 | epmd (peer discovery) | -- |
| 25672 | Inter-node communication | -- |
| 35672-35682 | CLI tools | -- |
| 6000-6500 | Stream replication | -- |

### 19.2 Proxy Protocol

```ini
proxy_protocol = true   # Supports v1 (text) and v2 (binary)
# WARNING: Clients must support proxy protocol when enabled
```

### 19.3 Bandwidth Estimation Formula

```
Required bandwidth = message_rate * message_size * 1.10 * 8

Example:
  20,000 msg/s * 6,144 bytes * 1.10 * 8 = 1.056 Gbps
```

---

## Quick Reference: rabbitmqctl Commands

```bash
# Status & diagnostics
rabbitmq-diagnostics -q ping
rabbitmq-diagnostics -q status
rabbitmq-diagnostics -q check_running
rabbitmq-diagnostics -q check_local_alarms
rabbitmq-diagnostics -q alarms
rabbitmq-diagnostics -q listeners
rabbitmq-diagnostics -q check_port_connectivity
rabbitmq-diagnostics -q check_virtual_hosts
rabbitmq-diagnostics -q memory_breakdown --unit "MB"
rabbitmq-diagnostics -q cluster_status
rabbitmq-diagnostics observer
rabbitmq-diagnostics runtime_thread_stats
rabbitmq-diagnostics erlang_cookie_sources

# Queue management
rabbitmqctl list_queues name type messages messages_ready messages_unacknowledged
rabbitmq-queues rebalance quorum
rabbitmq-queues grow <node> all
rabbitmq-queues shrink <node>

# Connection/channel management
rabbitmqctl list_connections name peer_host peer_port state channels
rabbitmqctl list_channels name connection consumer_count messages_unacknowledged
rabbitmqctl suspend_listeners
rabbitmqctl resume_listeners

# Cluster management
rabbitmqctl cluster_status
rabbitmqctl join_cluster rabbit@node1
rabbitmqctl forget_cluster_node rabbit@deadnode
rabbitmqctl force_boot

# Memory management
rabbitmqctl set_vm_memory_high_watermark 0.6
rabbitmqctl set_vm_memory_high_watermark absolute "4G"

# Policy management
rabbitmqctl set_policy <name> "<pattern>" '<json>' --priority <N> --apply-to <type>
rabbitmqctl list_policies

# Limits
rabbitmqctl set_vhost_limits -p <vhost> '<json>'
rabbitmqctl set_user_limits <user> '<json>'

# Plugins
rabbitmq-plugins enable rabbitmq_prometheus
rabbitmq-plugins enable rabbitmq_management
rabbitmq-plugins list
```
