# This is a reference document as to what are the prompts entered by the developer to claude code on migration 
# Use this as a guideline for migration 
As a prerequisite first create the baseline structure for react and .net core web api and have all folders in the same workspace in VS Code so that claude code can reference them from the terminal

# Prompt A Create a spec from the legacy code (one file at a time)
 Use Shift Tab to launch the plan mode 
use planning agents to reverse engineer the page c:\Development\PWA-Wells-Permit-WebAp
  p\wellspermit-ecomm-web-jboss\src\main\webapp\app_proj_locmap.jsp and generate a        
  specification . The spec should first specify what the web page does and  please save the plan into a file  under spec folder <give the folder path>

  # Prompt B Use the spec to generate the plan
  c:\Development\PWA-Wells-Permit-WebApp\spec\spec_app_proj_locmap.md in this spec I
  want to set up instructions for the migration how each of the pieces can now be used    
  to generate the migration , please plan using planning agents    

  # Prompt C Create an agent to generate the spec
  Please create an agent called agent-create-spec-from-jsp which requires user input for  
  the file to be processed to spec generation under here                                  
  c:\Development\PWA-Wells-Permit-WebApp\.claude\agents  

  # Prompt D Create an agent to generate the migration plan 
Please create an agent called agent-create-execution-migration-from-spec  which         
  requires user input for                                                                 
    the file to be processed from the generated spec file and create the plan under       
  c:\Development\PWA-Wells-Permit-WebApp\plan-execution and place the agent under         
                                                                                          
    c:\Development\PWA-Wells-Permit-WebApp\.claude\agents     
  # Prompt E Create an agent to generate a test scipt 
 Please create an agent which will generate a playwright script to test the web page   
  generated under                                                                         
  c:\Development\PWA-Wells-Permit-WebApp\frontend\pwa-wells-permit-web\src\pages        
                                                                                   
   use the spec created under the spec folder . call the agent                          
  agent-test-migration-from-spec  which requires user input for                    
    the file to be processed from the generated react page and use the generated spec     
  file for defining the testing criteria and create the test under                        
  c:\Development\PWA-Wells-Permit-WebApp\tests and place the agent under                  
                                                                                          
    c:\Development\PWA-Wells-Permit-WebApp\.claude\agents  
  # Final Sequence of steps to achieve migration
  Understand the application which needs to be migrated
  Create the baseline scafoldded frontend and backend code base 
  
The best way to get a ducessfull migration is to make one full end to end flow based on your expected result  

 - Define the Spec agent to generate a requirements definition
 - Define the Code agent to migrate the code based on the spec 
 - Exit from the terminal so that the agents show in the /agents 
  
  

  - Run the Spec and Code agent for each jsp file to generate the migrated code (Multiple Agents can be invoked the same time and run on the background Ctrl+B)

 @"agent-create-spec-from-jsp (agent)" c:\Development\PWA-Wells-Permit-WebApp\wellspermi 
  t-ecomm-web-jboss\src\main\webapp\app_work_wellsmap.jsp  


@"agent-create-execution-migration-from-spec (agent)"                              
  c:\Development\PWA-Wells-Permit-WebApp\plan-execution\app_proj_locmap_migration.md 


   @"agent-migrate" app_work_wellsmap.jsp — use the spec at spec/spec_app_work_wellsmap.md and
  ▎ execution plan at plan-execution/app_work_wellsmap_execution.md"`

Note : Some agent may not need Sonnet / Opus like code reviewer , analysis for those use Haiku to reduce usage

Commands being frequently used 
  /usage
  /clear
  /context
  /agents
  
