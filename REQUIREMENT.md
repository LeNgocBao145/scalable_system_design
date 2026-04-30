# Scalable System Design & Implementation
**Project Level:** Intermediate  
**Focus:** Infrastructure, Load Balancing, and Database Scaling (Read/Write Splitting)

---

## 1. Project Overview
The objective of this project is to build a functional, scalable backend infrastructure from scratch. You will move beyond simple application development to focus on how traffic is distributed and how data remains consistent across multiple nodes. You are required to set up a load-balanced environment with a replicated database architecture.

## 2. System Architecture Requirements
Your implementation must consist of the following main components:
* **Load Balancer (Nginx or HAProxy):** Acts as the single entry point. It must distribute incoming traffic to the backend nodes using a Round Robin or Least Connections algorithm.
* **Application Layer (2x API Nodes):** Two identical instances of a REST API (Node.js, Python, Go, etc.) running on separate ports or containers.
* **Database Layer (Master-Slave Replication):**
    * **Master Node:** Handles all **Write** / **Read** operations (INSERT, UPDATE, DELETE, GET).
    * **Slave Node (Read Replica):** Synchronizes data from the Master and handles **Read** operations (GET).

## 3. Functional Requirements (The API)
The API logic is intentionally kept simple to focus on the infrastructure setup. It must include:
* **POST `/products`:**
    * **Action:** Validates and saves product data (Name, Price) into the **Master Database**.
    * **Response:** Success message and the data created.
* **GET `/products`:**
    * **Action:** Fetches the list of products from the **Slave Database**.
    * **Response:** List of products + **Server Metadata** (e.g., `"processed_by": "Node_A"`). This is crucial to prove the Load Balancer is working.

## 4. Technical Implementation Steps (Step-by-Step)
You must document and record each of the following phases:

### Phase 1: Database Replication Setup
1.  Configure the **Master** node.
2.  Configure the **Slave** node.
3.  Verify synchronization by inserting data into Master and checking the Slave.

### Phase 2: API Development & Read/Write Splitting
1.  Implement the API logic.
2.  **Critical:** Configure the app to use two different connection strings: one for Writes (Master IP) and one for Reads (Slave IP).

### Phase 3: Infrastructure & Load Balancing
1.  Deploy two instances of the API.
2.  Configure the Load Balancer to proxy requests to both API nodes.
3.  Ensure the Load Balancer performs health checks (optional but recommended).

### Phase 4: Verification & Stress Test
1.  Use `curl` or Postman to send multiple requests.
2.  Verify that the "Server ID" in the response toggles between Node 1 and Node 2.
3.  Verify that data written to the Master is visible when querying the Slave.

## 5. Deliverables

### A. Technical Documentation (PDF or Markdown)
* **System Architecture Diagram:** A visual representation of your setup.
* **Configuration Snippets:** Key settings for Nginx, Database, and your API’s database connection logic.
* **Setup Guide:** A clear, step-by-step manual that a peer could follow to reproduce your environment.

### B. Video Demonstration
* **Duration:** 5 - 10 minutes.
* **Walkthrough:** Briefly show the code and configuration files.
* **Live Demo:** 1. Show a `POST` request saving to the Master.
    2. Show `GET` requests being balanced between two nodes.
    3. **The "Chaos" Test:** Manually shut down one API node and show that the system remains operational via the second node.

## 6. Evaluation Criteria

| Criteria | Weight | Description |
| :--- | :--- | :--- |
| **System Functionality** | 40% | Load balancer works; DB replication is active; API handles requests. |
| **Read/Write Splitting** | 20% | Correct routing of queries to Master vs. Slave. |
| **Fault Tolerance** | 10% | The system handles a single node failure gracefully. |
| **Documentation Quality** | 15% | Clear, concise, and technically accurate step-by-step guide. |
| **Video Presentation** | 15% | Professionalism, clarity of explanation, and successful live demo. |

* **Advanced Implementation: 2.0 points**
    Full system with Load Balancer + 2 API Nodes + **Master-Slave Database Replication** (Read/Write splitting).
* **Basic Implementation: 1.0 points**
    System with Load Balancer + 2 API Nodes + **Single Database Node** (No replication).

## 7. Submission Instructions
* **Deadline:** 6:00 PM, September 5th, 2026.
* **Format:** A ZIP file (`[MSSV].zip`) containing the PDF and a link to the Video (YouTube) or a GitHub Repository link containing all files.