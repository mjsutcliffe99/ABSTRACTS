# ABSTRACTS
Amsterdam Benchmark Suite for the Time and Resource Analysis of Clifford+T Simulators

## FAQs

<details><summary><strong>What is ABSTRACTS?</strong></summary>
ABSTRACTS is a benchmark suite and infrastructure for quantifying and comparing the efficiency of classical simulators of Clifford+T quantum circuits. It provides a broad consistent dataset of circuits, along with a virtual hardware provided by Amazon Web Services, enabling a fair comparison of methods.
</details>

<details><summary><strong>What is classical simulation?</strong></summary>
[TODO]
</details>

<details><summary><strong>Who can submit a simulator?</strong></summary>
Anyone is free to submit a simulator to be benchmarked on ABSTRACTS by submitting a Pull Request to this GitHub Repo. The only requirement is that the PR submission meets the specification outlined in [TODO] and we ask users not to frequently resubmit their simulators with incremental changes.
</details>

<details><summary><strong>How can I submit a simulator?</strong></summary>
[TODO]
</details>

<details><summary><strong>How often can I make a submission?</strong></summary>
There is no strict limit on submission frequency per person and if you have multiple techniques you wish to simulate we encourage you to submit each one. However, we ask users not to frequently resubmit their simulators with incremental changes. Instead, for simulators still undergoing optimisation, developers are encouraged to download the benchmark dataset and experiment locally before making a final submission for official benchmarking when ready.
</details>

<details><summary><strong>What happens after I submit a simulator?</strong></summary>
When a simulator is submitted for official benchmarking, it firstly undergoes a brief and shallow review to ensure it meets the specification and does not contain any malicious or cheating code. If approved, the PR will be accepted and the simulator added to the repo, which will trigger the automated benchmarking process. 
  
This involves the following automated steps:
  - Configure the AWS credentials
  - Launch the AWS virtual machine instance and wait for a response
  - SSH into it
  - Pull the latest GitHub repo to the VM instance
  - Execute the simulator for every circuit in the dataset and print the resulting measurements to a JSON file
  - Upon completion or timeout, commit and push this JSON file to the repo
  - Shut down the VM instance
  - Update the interactive plots on the repo to include the results of the new simulator
</details>

<details><summary><strong>How long does it take to benchmark a simulator?</strong></summary>
This depends on the efficiency of the submitted simulator but examples range from [TODO], and a hard timeout limit is set at [TODO] hours.
</details>

<details><summary><strong>What hardware are the benchmarks run on?</strong></summary>
[TODO]
</details>

