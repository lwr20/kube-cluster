import os
import numpy
import matplotlib.pyplot as pylab
import json
import subprocess
import re
from dateutil import parser
from subprocess import check_output

# Time extract regex.
start_re = re.compile("Started: ([0-9]+\.[0-9]+)")
end_re = re.compile("Completed: ([0-9]+\.[0-9]+)")

# Stores mapping of start time to elapsed time.
elapsed_by_start_time = {}

# Get all pod names.
all_pods = check_output(["kubectl", "get", "pods", "-o", "json"])
all_pods = json.loads(all_pods)["items"]

# Get all "getter" pod names.
pod_names = [p["metadata"]["name"] for p in all_pods
                if "getter" in p["metadata"]["name"]]

# Those that we fail to parse.
failed = []

# Arrays for scatter.
start_times = []
elapsed_times = []
end_times = []

# For each pod, get its logs.
for p in pod_names:
    logs = check_output(["kubectl", "logs", p])
    try:
        start_time = float(start_re.findall(logs)[0])
        end_time = float(end_re.findall(logs)[0])
    except IndexError:
        print "WARN: Missing start / end time"
        print logs
        failed.append((p, logs))
        continue

    # Determine the elapsed time and store in the mapping dict.
    elapsed = end_time - start_time 
    times = elapsed_by_start_time.setdefault(start_time, [])
    times.append(elapsed)

    # Store the X,Y arrays - start time, elapsed time, respectively.
    start_times.append(start_time)
    elapsed_times.append(elapsed)
    end_times.append(end_time)

# Sort all of the start times into an array.
ordered_start_times = sorted(start_times) 
ordered_end_times = sorted(end_times) 

for s in ordered_start_times:
    print s, elapsed_by_start_time[s]

print "%s failed to get logs" % len(failed)

# Create histogram.
vals = []
for _, l in elapsed_by_start_time.iteritems():
    vals += l
pylab.hist(vals)
pylab.xlabel('time-to-connectivity')
pylab.show()

# Calculate start times, shifted to account
# for the first pod to start.
min_x = ordered_start_times[0]
x = [(t-min_x) for t in start_times]

# Plot data.
pylab.plot(x, elapsed_times, 'ro')
pylab.show()
