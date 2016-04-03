import os
import numpy
import pylab
import json
import subprocess
import re
from dateutil import parser
from subprocess import check_output

# Time extract regex.
time_re = re.compile("(\d\d:\d\d:\d\d)")

# Stores mapping of start time to elapsed time.
mapping = {}

# Get all pod names.
all_pods = check_output(["kubectl", "get", "pods", "-o", "json"])
all_pods = json.loads(all_pods)["items"]

# Get all "getter" pod names.
pod_names = [p["metadata"]["name"] for p in all_pods
                if "getter" in p["metadata"]["name"]]

# Those that we fail to parse.
failed = []

# Arrays for scatter.
x = []
y = []

# For each pod, get its logs.
for p in pod_names:
    logs = check_output(["kubectl", "logs", p])
    times = time_re.findall(logs)
    try:
        start_time = times[0]
        end_time = times[1]
    except IndexError:
        print "WARN: Missing start / end time"
        print logs
        failed.appen((p, logs))
        continue

    # Determine the elapsed time and store in the mapping dict.
    elapsed = parser.parse(end_time) - parser.parse(start_time)
    times = mapping.setdefault(start_time, [])
    times.append(elapsed.seconds)
    x.append(parser.parse(start_time))
    y.append(elapsed.seconds)

starts = mapping.keys()
starts = sorted(starts, key=lambda d: map(int, str(d).split(':')))

for s in starts:
    print s, mapping[s]

print "%s failed to get logs" % len(failed)

# Create histogram.
vals = []
for _, l in mapping.iteritems():
    vals += l
pylab.hist(vals)
pylab.xlabel('time-to-connectivity')
pylab.show()

# Scatter plot - time vs start time.
# Change X into seconds from first.
min_x = starts[0]
x = [(i-parser.parse(min_x)).seconds for i in x]
pylab.plot(x, y, 'ro')
pylab.show()
