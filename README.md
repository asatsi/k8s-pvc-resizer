# k8s-pvc-resizer
Kubernetes PVC Resizer Script
# Objective
Automate PVC resizing since PVC can be expanded but cannot be shrunk in Kubernetes. This script would help in doing both. Especially this is helpful when you have kubernetes stateful sets which gets specific bounded claims and cannot be readily resized.
