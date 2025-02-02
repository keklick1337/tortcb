# **TORTCB – Tor TCP Chain Balancer**

**Author**: Vladislav Tislenko aka [keklick1337](https://github.com/keklick1337)

`TORTCB` is a two-part solution allowing you to:

1. Expose an existing **TCP service** (on your Docker host) over multiple **Tor hidden services**.
2. Load-balance incoming onion traffic across **separate Tor clients**, ensuring multiple independent Tor circuits and avoiding bandwidth overload on a single tunnel.

It consists of two Docker images:

1. **`tor_forward/`**  
   Creates multiple Tor hidden services, each forwarding traffic to a host-local TCP port (e.g., `127.0.0.1:5000`). Generates a `domains.list` with `<onion>:<port>` lines.  
2. **`haproxy_receiver/`**  
   Reads `domains.list`, starts **N** separate Tor clients (one per onion domain), and uses `socat` to route traffic locally. An **HAProxy** instance load-balances across all local endpoints. Provides an optional stats panel.

This structure effectively forms a **Tor TCP Chain Balancer** for a single host-based TCP service, scaling onion endpoints while distributing inbound load.

---

## **Repository Layout**

```
.
├── haproxy_receiver/
│   ├── Dockerfile
│   ├── haproxy.cfg.template
│   └── entrypoint.sh
├── tor_forward/
│   ├── Dockerfile
│   ├── torrc.template
│   └── entrypoint.sh
└── README.md
```

---

## **1) Build & Run Manually (Without `docker-compose`)**

### **1.1) `tor_forward`**

1. **Build** the image:
   ```bash
   cd tor_forward
   docker build -t tor_forward .
   ```
2. **Run** the container, pointing it to your host TCP service:
   ```bash
   docker run -d \
     --name tor_forward \
     -e HOST_IP=host.docker.internal \
     -e HOST_PORT=5000 \
     -e TOR_INSTANCES=3 \
     -e RANDOM_PORT_START=20000 \
     -v $(pwd)/data/tor_forward:/var/lib/tor/hidden_services \
     tor_forward
   ```
   - **`HOST_IP`** / **`HOST_PORT`**: The actual IP/port on your machine where your service is running.  
   - **`TOR_INSTANCES`**: How many hidden services to create.  
   - **`RANDOM_PORT_START`**: The first onion port (each instance increments by 1).  
   - This container writes out a file: `./data/tor_forward/domains.list` containing lines like `xyzabcd1234.onion:20000`, etc.

### **1.2) `haproxy_receiver`**

After `tor_forward` starts and generates `domains.list`, do:

1. **Build** the image:
   ```bash
   cd haproxy_receiver
   docker build -t haproxy_receiver .
   ```
2. **Run** the container, mounting `domains.list`:
   ```bash
   docker run -d \
     --name haproxy_receiver \
     -e HAPROXY_LISTEN_PORT=9080 \
     -e BASE_LOCAL_PORT=30000 \
     -e BASE_SOCKS_PORT=9050 \
     -e STATS_PORT=9090 \
     -e STATS_USER=admin \
     -e STATS_PASS=mypassword \
     -v $(pwd)/data/tor_forward/domains.list:/etc/domains.list:ro \
     -p 9080:9080 \
     -p 9090:9090 \
     haproxy_receiver
   ```
   - **`domains.list`** is read from `/etc/domains.list` inside the container.  
   - Each onion domain gets its own Tor client (`SocksPort = 9050 + i - 1`), `socat` listener (`30000 + i - 1`), and an HAProxy backend.  
   - External connections on **port 9080** are load-balanced across these onion endpoints.  
   - **Stats** can be accessed via `http://<docker_host>:9090/stats` with your configured credentials.

---

## **2) Example using Docker Compose**

A minimal `docker-compose.yml` might look like this:
```yaml
version: "3.8"

services:
  tor_forward:
    build: ./tor_forward
    container_name: tor_forward
    environment:
      - HOST_IP=host.docker.internal
      - HOST_PORT=5000
      - TOR_INSTANCES=5
      - RANDOM_PORT_START=20000
    volumes:
      - ./data/tor_forward:/var/lib/tor/hidden_services

  haproxy_receiver:
    build: ./haproxy_receiver
    container_name: haproxy_receiver
    environment:
      - HAPROXY_LISTEN_PORT=9080
      - BASE_LOCAL_PORT=30000
      - BASE_SOCKS_PORT=9050
      - STATS_PORT=9090
      - STATS_USER=admin
      - STATS_PASS=mypassword
    volumes:
      - ./data/tor_forward/domains.list:/etc/domains.list:ro
    ports:
      - "9080:9080"
      - "9090:9090"
```
1. `tor_forward` writes `<onion>:<port>` lines to `domains.list`.  
2. `haproxy_receiver` reads `domains.list` and sets up **N** local Tor/socat combos.  
3. Expose `9080` for the main load-balancing entry point and `9090` for the HAProxy stats page.
4. You can split `docker-compose.yml`.

**Running**:
```bash
docker-compose up -d --build
```
Check logs to confirm hidden services were generated and that HAProxy is up with multiple onion backends.

---

## **3) Environment Variables**

### **`tor_forward/`**  
- **`HOST_IP`** (default: `host.docker.internal`)  
  IP or hostname to forward inbound onion connections to.  
- **`HOST_PORT`** (default: `5000`)  
  Host TCP port of your actual service.  
- **`TOR_INSTANCES`** (default: `3`)  
  Number of hidden services.  
- **`RANDOM_PORT_START`** (default: `20000`)  
  The first onion port to use; each subsequent service increments by 1.  
- **`TOR_DATA_DIR`** (default: `/var/lib/tor/hidden_services`)  
  Persistent volume for hidden service keys/hostnames.

### **`haproxy_receiver/`**  
- **`HAPROXY_LISTEN_PORT`** (default: `80`)  
  The main port to accept inbound connections (exposed externally).  
- **`BASE_SOCKS_PORT`** (default: `9050`)  
  The starting Tor SocksPort for each onion domain.  
- **`BASE_LOCAL_PORT`** (default: `30000`)  
  The starting local port for socat listeners.  
- **`STATS_PORT`** (default: `9090`)  
  HAProxy stats page port.  
- **`STATS_USER`** / **`STATS_PASS`** (defaults: `admin` / `adminpass`)  
  Credentials for stats page.

---

## **4) Notes & Tips**

- On **Linux**, `host.docker.internal` may be unsupported; replace with an actual host IP (e.g., `172.17.0.1`) or use `--network host`.  
- Check container logs to see the onion addresses, ports, and whether Tor started successfully.  
- If you run many onion services or many Tor clients, watch your system’s resource usage (RAM/CPU).  
- The generated onion addresses persist in the mounted volume (`data/tor_forward`), so you can keep them stable across container restarts.

---

## **5) License and Attribution**

No specific license is provided here. The project is an example of bridging and load-balancing through Tor.  
Contact **[keklick1337](https://github.com/keklick1337)** for any questions or contributions.