using Conda

Conda.add("ase", channel = "conda-forge")
Conda.add("rdkit", channel = "conda-forge")
Conda.add("pymatgen", channel = "conda-forge")
try
  Conda.version("mkl")
  Conda.rm("mkl")
catch e
  @info "\nPre-existing MKL is uninstalled to avoid known issues.\nNow reinstalling the MKL..."
finally
  Conda.add("mkl")
end
