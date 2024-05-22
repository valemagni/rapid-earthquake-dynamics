#!/bin/bash
set -euov pipefail

script_dir=$(dirname "$0")


usgs_event_id_or_dtgeo_file=$1

if [ $# -eq 1 ]; then
    finite_fault_fn="tmp/basic_inversion.param"
    suffix_arg=""
elif [ $# -eq 2 ]; then
    finite_fault_fn="../$2"
    file_basename=$(basename "$2")
    suffix_arg="--suffix ${file_basename%.*}"
else
    echo "illegal number of parameters, usage:"
    echo "$0 usgs_event_id_or_dtgeo_file"
    echo "or"
    echo "$0 usgs_event_id_or_dtgeo_file kinematic_model_fn"
    exit 1
fi


folder_name=$($script_dir/../src/get_usgs_finite_fault_data.py $usgs_event_id_or_dtgeo_file $suffix_arg)
cd $folder_name
read lon lat _ < tmp/hypocenter.txt
proj="+proj=tmerc +datum=WGS84 +k=0.9996 +lon_0=${lon} +lat_0=${lat}"
echo $proj > tmp/projection.txt

$script_dir/../SeisSol/preprocessing/science/kinematic_models/infer_fault_mesh_size_and_spatial_zoom.py $finite_fault_fn --proj "${proj}"
read inferred_spatial_zoom < tmp/inferred_spatial_zoom.txt
read inferred_fault_mesh_size < tmp/inferred_fault_mesh_size.txt
$script_dir/../preprocessing/science/kinematic_models/generate_FL33_input_files.py $finite_fault_fn --spatial_zoom $inferred_spatial_zoom --proj "${proj}"  --interpolation_method cubic --write
$script_dir/../preprocessing/science/kinematic_models/modify_FL33_34_fault_instantaneous_slip.py
$script_dir/../preprocessing/science/automated_workflow_dyn_from_kin/generate_usgs_finite_fault_mesh.py --fault_mesh_size $inferred_fault_mesh_size
module load pumgen
pumgen -s msh4 tmp/mesh.msh
$script_dir/../preprocessing/science/automated_workflow_dyn_from_kin/generate_input_seissol_fl33.py
if [ -z "$suffix_arg" ]; then
    $script_dir/../preprocessing/science/automated_workflow_dyn_from_kin/extract_velocity_model_from_usgs_fsp.py
else
    echo "using slipnear velocity model"
    cp $script_dir/../preprocessing/science/automated_workflow_dyn_from_kin/input_files/vel_model_slipnear.txt tmp
    $script_dir/../preprocessing/science/automated_workflow_dyn_from_kin/generate_velocity_model_files_slipnear.py
    $script_dir/../preprocessing/science/kinematic_models/compute_moment_rate_from_finite_fault_file.py $finite_fault_fn yaml_files/usgs_material.yaml  --proj "${proj}"
fi

echo "now run seissol"
