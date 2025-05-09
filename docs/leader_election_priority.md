Leader Election Priority
========================

Purpose
-------
The main goal is to prioritize member nodes for the next leader election. Raft uses randomized timers so that it is hard to make a deterministic decision. In this library, leader election will still be probabilistic but more predictable.


New Definitions
---------------
We define `priority_` in [`srv_config`](../include/libnuraft/srv_config.hxx), which is an integer from 0 to any value. Priority `0` is a special value, so a node with zero priority will never be a leader. All nodes in the same Raft group will be aware of all members' priorities.

Each node has an internal local value *target priority*, which is initially set to `max(priority of all nodes)`.


Detailed Mechanism
------------------
When the current leader is alive, whenever a follower receives a heartbeat, it updates its target priority to the initial value: `max(priority of all nodes)`.

If the leader dies and an election timeout happens in a follower node, it first compares its local target priority with its own priority (i.e., `priority_`). If `priority_ < target_priority`, it does not initiate leader election and waits for the next election timeout. Otherwise, it initiates a leader election. If next leader is not elected until next election timeout, it exponentially lessens its local target priority, for example `target_priority = target_priority * 0.8`. And the minimum value of target priority should be `1`.

Once a follower node receives a vote request, it compares its local target priority with the priority of the candidate. If `candidate_priority < target_priority`, it rejects the vote request. If not, it makes a decision properly, the same as in the original Raft algorithm.


Examples
--------

* 5 nodes (priority): S1 (100), S2 (100), S3 (80), S4 (80), S5 (50)
* Initial leader: S1
* Tn: Sn's target priority, Pn: Sn's priority

#### Leader election while the highest priority node is alive ####
```
S1      S2      S3      S4      S5
|       |       |       |       |   Initially T1-5 are set to 100
X       |       |       |       |   S1 is gone
        |       X       |       |   S3's election timer expires
        |       |       |       |       => T3: 100, P3: 80
        |       |       |       |       => Since T3 > P3, do nothing
        X       |       |       |   S2's election timer expires
        |       |       |       |       => T2: 100, P2: 100
 <------X------>|------>|------>|       => Since T2 <= P2, initiate vote
        |<------X-------X-------X   Since P2 >= T3, T4, T5, accept the request
        X       |       |       |   S2 becomes a leader
        |       |       |       |
```

#### Leader election while all highest priority nodes are offline ###
```
S1      S2      S3      S4      S5
|       |       |       |       |   Initially T1-5 are set to 100
X       X       |       |       |   S1 and S2 are gone
                X       |       |   S3's election timer expires
                |       |       |       => T3: 100, P3: 80
                |       |       |       => Since T3 > P3, do nothing
                |       |       X   S5's election timer expires
                |       |       |       => T5: 100, P5: 50
                |       |       |       => Since T5 > P5, do nothing
                |       X       |   S4's election timer expires
                |       |       |       => T4: 100, P4: 80
                |       |       |       => Since T4 > P4, do nothing
                X       |       |   S3's election timer expires
                |       |       |       => Leader is not elected, set T3 = 80
                |       |       |       => T3: 80, P3: 80
 <------ <------X------>|------>|       => Since T3 <= P3, initiate vote
                |<------X-------X   Since P3 < T4 and T5, reject the request
                |       |       X   S5's election timer expires
                |       |       |       => Leader is not elected, set T5 = 80
                |       |       |       => T5: 80, P5: 50
                |       |       |       => Since T5 > P5, do nothing
                |       X       |   S4's election timer expires
                |       |       |       => Leader is not elected, set T4 = 80
                |       |       |       => T4: 80, P4: 80
 <------ <------|<------X------>|       => Since T4 <= P4, initiate vote
                X------>|<------X   Since P4 >= T3 and T4, accept the request
                |       X       |   S4 becomes a leader
                |       |       |
```

Note
----
* If the priorities of all nodes are even, leader election is exactly the same as the original algorithm.
* If all highest priority nodes are gone at the same time, the overall leader election time gets longer, as we waste at least one election time slot for reducing target priority.


Allowing a Zero-Priority Leader
-------------------------------
As aforementioned, a zero-priority member can never be a leader. However, there are scenarios where it might be the only viable candidate for leadership. Consider the following sequence of events:

* 5 nodes (priority): S1 (100), S2 (50), S3 (50), S4 (50), S5 (0)
* Initial leader: S1
* S1 replicates the latest log to S2 and S5.
* Before replicating the log to S3 and S4, S1 and S2 go offline.
* Now S5 is the only member with the latest log, but S5 does not initiate the vote due to its priority.
* Consequently, the entire Raft group is stuck.

To prevent this situation, there is an option called `allow_temporary_zero_priority_leader_`, which is enabled by default. If a zero-priority member is the only candidate, it will initiate the vote and become the temporary leader. Once in leadership, it replicates the latest log to the other members, then automatically resigns and yields leadership to another member. This process allows the Raft group to elect a new leader and continue functioning smoothly.

