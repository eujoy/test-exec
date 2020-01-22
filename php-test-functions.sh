# Custom function
# Execution : phpFilesModified [-f] [-u]
# Example   :
#    - Run for modified test files only
#	     phpFilesModified -u
#    - Run for modified files only
#        phpFilesModified -f
#    - Run for all modified files and unit test files
#        phpFilesModified -f -u
function phpFilesModified() {
	usage="
Script usage: $(basename $0) [-f] [-u]
By default both searching for modified files and modified unit test files is disabled
Explanation of allowed flags/arguments :
  - Helping :
    -h             : Displays the usage of the script (this description)
  - Optional arguments :
    -f  : Search for files that have been modified and find the respective test files (same name with 'Test' suffix)
    -u  : Search for unit test files that have been modified
"

	check_files=false
	check_unit_tests=false

	while getopts fhu OPTION; do
		case "$OPTION" in
			f)
				check_files=true
				;;
			u)
				check_unit_tests=true
				;;
			h)
				echo $usage >&2
				return
				;;
			?)
				echo $usage >&2
				return
				;;
			*)
				echo "Invalid arguments provided!!" >&2
				echo $usage >&2
				return
				;;
		esac
	done

	declare -a files_affected
	declare -a tests_affected

	[[ $check_files == true ]] && files_affected=($(git status | grep '.php' | grep -v 'deleted:' | grep -v 'Test.php' | sed s/modified:// | sed 's/src/tests\/Test/' | sed 's/.php/Test.php/' | grep -v 'renamed:'))
	[[ $check_unit_tests == true ]] && tests_affected=($(git status | grep 'Test.php' | grep -v 'deleted:' | sed s/modified://))

	# Cleanup the test files to be executed in order to remove duplicates
	combined=( "${tests_affected[@]}" "${files_affected[@]}" )
	unique_test_files=($(echo "${combined[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

	if [ -z "$unique_test_files" ]; then
		echo "No test files to run found!!"
		return
	fi

	__runTests $unique_test_files
}

# Custom function
# Execution : phpTestCase -t <name of test> [-n <name of file where the test exists>] [-c|-f]
# Example   : 
#    - Run any occurance the test case  :
#        phpTestCase -t testGetMessageOnDriverComment -c
#    - Run only the test case from file :
#        phpTestCase -t testGetMessageOnDriverComment -f MessageServiceTest.php -c
#    - Run the whole file of any occurance of the test case : 
#        phpTestCase -t testGetMessageOnDriverComment -f
function phpTestCase() {
	cmd="php vendor/bin/phpunit"

	usage="
Script usage: $(basename $0) -t test_case_name [-c | -f] [-n file_name] [-e]
Explanation of allowed flags/arguments :
  - Helping :
    -h             : Displays the usage of the script (this description)
  - Mandatory arguments :
    -t <test case> : The test case to search for and run
  - Optional arguments :
    -c             : Run the test case only as it is found in any test file <Defaults to 'case'>
    -e             : Execute the exactly the test case that has been provided
    -f             : Run the whole file where the test case is found <Defaults to 'case'>
    -n <file name> : The file in which to search for the provided test case and execute if found in there
"

	exact_test=false
	extra_field=""
	extra_text=""
	test_file_name=""
	test_case_name=""
	execution_type=""

	while getopts cd:efhn:t: OPTION; do
		case "$OPTION" in
			d)
				test_files_directory=${OPTARG}
				;;
			n)
				[[ ${OPTARG} != "" ]] && test_file_name="/${OPTARG}"
				;;
			t)
				[[ ${OPTARG} != "" ]] && test_case_name=${OPTARG}
				;;
			f)
				[[ ${execution_type} == "" ]] && execution_type="file"
				;;
			c)
				[[ ${execution_type} == "" ]] && execution_type="case"
				;;
			e)
				exact_test=true
				;;
			h)
				echo $usage >&2
				return
				;;
			?)
				echo $usage >&2
				return
				;;
			*)
				echo "Invalid arguments provided!!" >&2
				echo $usage >&2
				return
				;;
		esac
	done

	if [[ $test_case_name == "" ]]; then
		echo "Mandatory argument not provided!!" >&2
		echo $usage >&2
		return
	fi

	[[ $execution_type == "case" || $execution_type == "" ]] && extra_field="--filter ${test_case_name}" extra_text=" | Test Case Filter : ${test_case_name}"
	[[ $exact_test == true && $extra_field != "" ]] && extra_field="--filter /::${test_case_name}( with data set .*)?$/"

	if [ $exact_test == true ]; then
		testfiles=($(grep -Rw "${test_case_name}" tests/Test/* | awk -F':' '{print $1}'))
	else
		testfiles=($(grep -Rni "${test_case_name}" tests/Test/* | awk -F':' '{print $1}'))
	fi

	# Filter the file names found to avoid duplicates
	unique_test_files=($(echo "${testfiles[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

	for f in "${unique_test_files[@]}"
	do
		if [[ "$f" == *$test_file_name || $test_file_name == "" ]]; then
			printf "\e[93;4;255m\nRunning file : ${f}${extra_text}\e[0m\n\n"

			echo "$cmd ${f} ${extra_field}"
			
			eval "$cmd ${f} ${extra_field}"
		fi
	done
}

# Custom function
# Execute all the test files that have been modified themselves or the respective class has been modified
# as part of a branch as compared to develop branch.
# Example :
#    - Run all the modified test files and respective test files of modified files (compared to local develop)
#        phpTestBranchChanges
#    - Run modified files of branch compared to another branch
#        phpTestBranchChanges -d <destination branch>
#    - Run modified files of provided branch compared to default branch (develop)
#        phpTestBranchChanges -b <feature branch>
#    - Run modified files compared to remote branch (develop by default)
#        phpTestBranchChanges -r
#    - Run modified files of branch compared to another branch on remote
#        phpTestBranchChanges -b <feature branch> -d <destination branch> -r
function phpTestBranchChanges() {
	usage="
Script usage: $(basename $0) [-b feature_branch] [-d destination_branch] [-r]
By default this script is comparing the current branch (local) with the develop (local)
Explanation of allowed flags/arguments :
  - Helping :
    -h                    : Displays the usage of the script (this description)
  - Optional arguments :
    -b feature_branch     : Feature branch that we need to compare | Defaults to current branch
    -d destination_branch : Base branch to compare against | Defaults to develop branch
    -r                    : Define whether to compare remote or local branches
"

	feature_branch=""
	base_branch="develop"
	remote=false

	while getopts b:d:hr OPTION; do
		case "$OPTION" in
			b)
				feature_branch=${OPTARG}
				;;
			d)
				base_branch=${OPTARG}
				;;
			r)
				remote=true
				;;
			h)
				echo $usage >&2
				return
				;;
			?)
				echo $usage >&2
				return
				;;
			*)
				echo "Invalid arguments provided!!" >&2
				echo $usage >&2
				return
				;;
		esac
	done

	[[ $remote == true && $feature_branch == "" ]] && feature_branch=$(git branch | grep \* | cut -d ' ' -f2)
	[[ $remote == true ]] && feature_branch="origin/${feature_branch}" base_branch="origin/${base_branch}"

	# Getting the modified test files to run them
	tests_affected=($(git diff $base_branch $feature_branch | grep "+++" | grep 'Test.php' | sed s/"+++ b\\/"// | grep -v "vendor/"))
	
	# Getting the affected files to run the respective test files affected
	files_affected=($(git diff $base_branch $feature_branch | grep "+++" | grep "src/" | sed s/"+++ b\\/"// | sed s/.php/Test.php/ | sed s/src/"tests\/Test"/ | grep -v "vendor/"))

	# Cleanup the test files to be executed in order to remove duplicates
	combined=( "${tests_affected[@]}" "${files_affected[@]}" )
	unique_test_files=($(echo "${combined[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

	__runTests $unique_test_files
}

# Run all the test files on the array provided
function __runTests() {
	test_files=("$@")

	cmd="php vendor/bin/phpunit"

	for f in "${test_files[@]}"
	do
		if [ -f "$f" ]; then
			printf "\e[93;4;255m\nRunning file : ${f}\e[0m\n\n"
			eval "$cmd ${f}"
		fi
	done
}
