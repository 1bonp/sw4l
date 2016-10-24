bitbake -e package_name > package_name.env
./get_vars (modify package_name.env file in script)

We generate a file package_name.vars: 
	variables of type "VAR=" are replaced with "yocto_vars"["variable_name"]="value"
	fonctions are replaced as yocto_fonctions=["fonction_name"]='{}'
	python fonction are replaces as yocto_python_fonctions=["fonction_name"]='{}' 	 


To display SRC_URI variable: 
echo ${yocto_vars[SRC_UNI]}
or
for uri in ${yocto_vars[SRC_UNI]}; do echo "$uri"; done
 

