# Create and enter the pipeline home directory

cd ../

sudo mkdir -p /opt/transcriptomic-pipeline
sudo chown $USER:$USER /opt/transcriptomic-pipeline
cd /opt/transcriptomic-pipeline

# Clone the orchestrator and all 6 dependent modules
git clone https://github.com/transcriptomic-pipeline/e2e.git
git clone https://github.com/transcriptomic-pipeline/qc.git
git clone https://github.com/transcriptomic-pipeline/alignment.git
git clone https://github.com/transcriptomic-pipeline/dge.git
git clone https://github.com/transcriptomic-pipeline/fusion.git
git clone https://github.com/transcriptomic-pipeline/alt-splicing.git
git clone https://github.com/transcriptomic-pipeline/transcript-variants.git

cd e2e

# Edit the "pipeline_master.conf" configuration file based on your pipeline run preferences and preffered input files/paths/settings and run the "run_e2e.sh" script to start.
# Example: edit the configuration file "gedit pipeline_master.conf" and run the e2e pipeline "bash run_e2e.sh pipeline_master.conf"

echo "edit the conf file pipeline_master.conf"
echo "bash run_e2e.sh -h"
echo "Example Usage: bash run_e2e.sh path/to/pipeline_master.conf"