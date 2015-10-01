#
# $Id: Editor.pm,v 1.9 2009/02/01 18:06:05 banghart Exp $
#
# Copyright Michigan State University Board of Trustees
#
# This file is part of the PROM/SE Virtual Professional Development (VPD
# system.
#
# VPD is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# VPD is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with VPD; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# /home/httpd/html/adm/gpl.txt
#
# 
package Apache::Editor;
# File: Apache/Editor.pm
use CGI;
use Apache::Promse;
use Apache::Flash;
use JSON::XS;

use strict;
sub course_existing_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Existing','courses','existing',$active,'tabBottom',undef);
    return($tab_info);
}
sub course_add_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Add Course','courses','add',$active,'tabBottom',undef);
    return($tab_info);
}
sub course_edit_submenu {
    my ($active, $course_id) = @_;
    my %fields = ('courseid'=>$course_id,
                  'action'=>'edit',
                  'editcourse'=>'true');
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Edit Course','courses','edit',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub course_edit_courseonly {
    my ($active, $course_id) = @_;
    my %fields = ('courseid'=>$course_id,
                  'action'=>'edit',
                  'editcourse'=>'true');
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Edit Inter.','courses','editcourseonly',$active,'tabBottom',\%fields);
    return($tab_info);
}

sub course_build_submenu {
    my ($active, $course_id) = @_;
    my %fields = ('courseid'=>$course_id);
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Build Course','courses','build',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub course_addcourseonlyresource_submenu {
    my ($active, $course_id) = @_;
    my %fields = ('courseid'=>$course_id);
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Interstitial','courses','addcourseonlyresource',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub resource_browse_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Browse','resources','browse',$active,'tabBottom',undef);
    return($tab_info);
}
sub resource_add_submenu {
    my ($active) = @_;
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Upload','resources','add',$active,'tabBottom',undef);
    return($tab_info);
}
sub resource_edit_submenu {
    my ($active, $resource_id) = @_;
    my %fields = ('resourceid'=>$resource_id);
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Edit','resources','edit',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub resource_categories_submenu {
    my ($active, $resource_id) = @_;
    my %fields = ('resourceid'=>$resource_id);
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Categories','resources','categories',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub resource_tags_submenu {
    my ($active, $resource_id) = @_;
    my %fields = ('resourceid'=>$resource_id);
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','Add Tags','resources','tags',$active,'tabBottom',\%fields);
    return($tab_info);
}
sub resource_showvidslide_submenu {
    my ($active, $resource_id, $show_name) = @_;
    my %fields = ('resourceid'=>$resource_id,
                  'showname'=>$show_name,
                  'action'=>'showvidslide'
                  );
    my $tab_info = &Apache::Promse::tabbed_menu_item('editor','View','resources','showvidslide',$active,'tabBottom',\%fields);
    return($tab_info);
}

sub get_curriculum_selector {
	my ($r) = @_;
	my $profile = &Apache::Promse::get_user_profile($Apache::Promse::env{'user_id'});
	my $curricula = &Apache::Flash::get_curricula($$profile{'district_id'}, $$profile{'subject'});
	$r->print(JSON::XS::->new->pretty(1)->encode( \@$curricula));
}
# tabbed_menu_item($page, $title, $menu, $submenu, $active, $add_fields)
sub InsertRecord {
	my($r) = @_;
	my $fieldNames = $r->param('fieldName');
	my $fieldValues = $r->param('fieldValue');
	my $tableName = $r->param('tableName');
	my %fields;
	my $numFields = scalar(@$fieldNames);
	for (my $fieldNum = 0;$fieldNum < $numFields;$fieldNum++) {
		$fields{$$fieldNames[$fieldNum]} = $$fieldValues[$fieldNum];
	}
	my $newRecordId = &Apache::Promse::save_record($tableName, \%fields, 1);
}
sub editor_sub_tabs {
    my ($r) = @_;
    my @sub_tabs;
    my %tab_info;
    my $tab_info;
    my $tab_info_hashref;
    my $active = 1;
    my %fields;
    if ($env{'menu'} eq 'courses') {
        if (($env{'submenu'} eq 'existing') || ($env{'submenu'} eq 'add')) {
            $active = ($env{'submenu'} eq 'existing')?1:0;
            $tab_info_hashref = &course_existing_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &course_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
        } elsif (($env{'submenu'} eq 'edit') || ($env{'submenu'} eq 'build') ||
                  ($env{'submenu'} eq 'build') || ($env{'submenu'} eq 'addcourseonlyresource'))  {
            $active = ($env{'submenu'} eq 'existing')?1:0;
            $tab_info_hashref = &course_existing_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &course_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'edit')?1:0;
            $tab_info_hashref = &course_edit_submenu($active, $r->param('courseid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'build')?1:0;
            $tab_info_hashref = &course_build_submenu($active, $r->param('courseid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'addcourseonlyresource')?1:0;
            $tab_info_hashref = &course_addcourseonlyresource_submenu($active, $r->param('courseid'));
            push(@sub_tabs,{%$tab_info_hashref});
            if ($env{'submenu'} eq 'editcourseonly') {
                $active = ($env{'submenu'} eq 'editcourseonly')?1:0;
                $tab_info_hashref = &course_addcourseonlyresource_submenu($active, $r->param('courseid'));
                push(@sub_tabs,{%$tab_info_hashref});
            }
        }
    } elsif ($env{'menu'} eq 'resources') {
        if (($env{'submenu'} eq 'browse') || ($env{'submenu'} eq 'add')) {
            $active = ($env{'submenu'} eq 'browse')?1:0;
            $tab_info_hashref = &resource_browse_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &resource_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
        } elsif (($env{'submenu'} eq 'edit') || ($env{'submenu'} eq 'edit') ||
                  ($env{'submenu'} eq 'categories') || ($env{'submenu'} eq 'tags')||
                  ($env{'submenu'} eq 'showvidslide')) {
            $active = ($env{'submenu'} eq 'browse')?1:0;
            $tab_info_hashref = &resource_browse_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'add')?1:0;
            $tab_info_hashref = &resource_add_submenu($active);
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'edit')?1:0;
            $tab_info_hashref = &resource_edit_submenu($active, $r->param('resourceid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'categories')?1:0;
            $tab_info_hashref = &resource_categories_submenu($active, $r->param('resourceid'));
            push(@sub_tabs,{%$tab_info_hashref});
            $active = ($env{'submenu'} eq 'tags')?1:0;
            $tab_info_hashref = &resource_tags_submenu($active, $r->param('resourceid'));
            push(@sub_tabs,{%$tab_info_hashref});
            &Apache::Promse::logthis(&Apache::Promse::get_resource_type($r->param('resourceid')).' is the type');
            if (&Apache::Promse::get_resource_type($r->param('resourceid')) eq 'Video/Slide') {
                $active = ($env{'submenu'} eq 'showvidslide')?1:0;
                $tab_info_hashref = &resource_showvidslide_submenu($active, $r->param('resourceid'),$r->param('showname'));
                push(@sub_tabs,{%$tab_info_hashref});
            }
        }
    } elsif ($env{'menu'} eq 'curriculum') {
        $active = ($env{'submenu'} eq 'selectcurriculum')?1:0;
        #$tab_info = &Apache::Promse::tabbed_menu_item('editor','Select Curr.','curriculum','selectcurriculum',$active,'tabBottom',\%fields);
        #push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'addcurriculum')?1:0;
        #$tab_info = &Apache::Promse::tabbed_menu_item('editor','Add Curr.','curriculum','addcurriculum',$active,'tabBottom',\%fields);
        #push(@sub_tabs,{%$tab_info});
        if ($env{'curriculum_id'} ne 'undefined') {
            $active = ($env{'submenu'} eq 'develop')?1:0;
            #$tab_info = &Apache::Promse::tabbed_menu_item('editor','Develop','curriculum','develop',$active,'tabBottom',\%fields);
            #push(@sub_tabs,{%$tab_info});
        }
        $active = ($env{'submenu'} eq 'materials')?1:0;
        #$tab_info = &Apache::Promse::tabbed_menu_item('editor','Materials','curriculum','materials',$active,'tabBottom',\%fields);
        #push(@sub_tabs,{%$tab_info});
        $active = ($env{'submenu'} eq 'addmaterials')?1:0;
        #$tab_info = &Apache::Promse::tabbed_menu_item('editor','Add Material','curriculum','addmaterials',$active,'tabBottom',\%fields);
        #push(@sub_tabs,{%$tab_info});
    }
    return(\@sub_tabs);
}
sub editor_tabs_menu {
    my($r) = @_;
    my @tabs_info;
    my %fields;
    my $active;
    my $tab_info;
    $active = ($env{'menu'} eq 'home')?1:0;
    %fields = ('secondary'=>&editor_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('editor','Editor Home','home','',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'resources')?1:0;
    %fields = ('target'=>'resources',
              'secondary'=>&editor_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('editor','Resources','resources','browse',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'courses')?1:0;
    %fields = ('target'=>'courses',
               'secondary'=>&editor_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('editor','Mini Courses','courses','existing',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'curriculum')?1:0;
    %fields = ('secondary'=>&editor_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('editor','Curriculum','curriculum','selectcurriculum',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
    $active = ($env{'menu'} eq 'oldcurriculum')?1:0;
    %fields = ('secondary'=>&editor_sub_tabs($r));
    $tab_info = &Apache::Promse::tabbed_menu_item('editor','Curriculum (Flash)','oldcurriculum','selectcurriculum',$active,'tabTop',\%fields);
    push (@tabs_info,{%$tab_info});
#    $active = ($env{'menu'} eq 'code')?1:0;
#    %fields = ('secondary'=>'');
#    $tab_info = &Apache::Promse::tabbed_menu_item('editor','Code','code','',$active,'tabTop',\%fields);
#    push (@tabs_info,{%$tab_info});
    return(&Apache::Promse::tabbed_menu_start(\@tabs_info));
}
sub edit_curriculum {
	my($r) = @_;
	#     <script src="http://35.8.169.173/js/controllers.js">
	my $javascript = qq~
	<script src="https://ajax.googleapis.com/ajax/libs/angularjs/1.3.16/angular.min.js"></script>
    <script type="text/javascript">
        var curriculumApp = angular.module('curriculumApp', []);
        var statusMessage = 'initialized';
        curriculumApp.controller('CurriculumListCtrl', function (\$scope, \$http) {
	        \$scope.statusMessage = 'My message';
        	\$scope.loadCurricula = function() {
            	console.log('loading curricula');
            	\$scope.statusMessage = 'Loading curricula';
            	\$http.post('flash',{action:'getcurriculaJSON',
                        token:token}).
            	success(function(data, status, headers, config) {
                	\$scope.curricula = data['curricula'];
                	\$scope.statusMessage = 'Curricula loaded';	
        		}).
        		error(function(data, status, headers, config) {
            		console.log('error in http wrapper');
      			});

    		}
    		\$scope.setStatusMessage = function(message){
    			\$scope.statusMessage = message;
    		}
		});



		var currentSelected;
		var pageId = "editCurriculum";
		var token = "$env{'token'}";
		function setStatusMessage(message) {
			\$("#statusMessage").text(message);
		}
		function editCurriculumLoadFunctions() {
		    // each scrolling list has its own onloadHandler
		    // identified with the idPrefix for curriculum it is 'cur'
			curSLonloadHandler();
		}
	</script>
	~;
	$r->print($javascript);
	my $output = qq~
	<div ng-app="curriculumApp" ng-controller="CurriculumListCtrl">
	<div id="statusMessage">{{statusMessage}}</div>
    <div id="clickHere" ng-click="loadCurricula()">{{count}} + ' click'</div>
	<div id="curriculumScroller" style="text-align:left">
            <dir ng-repeat="curriculum in curricula">
              <dir ng-class-even="'o_table_row_even'" ng-class-odd="'o_table_row_odd'">{{curriculum.title}}</dir>
             
            </dir>
          
	</div>
	</div>
	~;
	$r->print($output);
	#&Apache::Flash::getcurriculaselector();
}
sub scrollingList {
	my($params) = @_;
	my $idPrefix = $$params{'idPrefix'};
	my $url = $$params{'url'};
	my $keepAliveURL = $$params{'keepAliveURL'};
	my $tableName = $$params{'tableName'};
	my $fieldName = $$params{'fieldName'};
	my $fieldNames = $$params{'fieldNames'};
	my $width = $$params{'width'};
	my $offset = $$params{'offset'};
	my $rowCount = $$params{'rowCount'};
	my %tableHash;
	my $token = $env{'token'};
	my $inputFields = '';
	my $temp_qry = $$params{'qry'};
	my %fields = ('query'=>"'$temp_qry'");
	my $temp_query_id = &Apache::Promse::save_record('temp_queries',\%fields,1);
	foreach my $fName (@$fieldNames) {
		$inputFields .= $fName . '<input type="text" name="'. $fName .'"> ' . '<br />'; 
	}
	my $htmlOut = qq~
	<div id="${idPrefix}scrollingList" style="width:${width}px;text-align:left">
		<div id="${idPrefix}Controls">
			<div id="${idPrefix}addRecord" onclick="${idPrefix}addRecordClicked(this)" style="float:left"> + </div>
			<div id="${idPrefix}deleteRecord" onclick="${idPrefix}deleteRecordClicked(this)" style="float:left"> - </div>
			<div id="${idPrefix}editRecord" onclick="${idPrefix}editRecordClicked(this)" style="float:right"> Edit </div>
		</div>
		<div style="clear:both"></div>
		<div id="${idPrefix}form" style="display:none;width:300px;height:200px;background-color:#eeffee" >
			<form>
			${inputFields}
			</form>
		</div>
		<div id="scroller" style="width:${width}px;height:600px;
			display:block;
			float:left;
			background-color:#ffffee;
			overflow:scroll">

		</div>
	</div>
	
	~;
	$tableHash{'html'} = $htmlOut;
	my $jsOut = qq~
	<script type="text/javascript">
	var ${idPrefix}keepAlive;
	${idPrefix}tempQueryId = $temp_query_id;
	${idPrefix}offset = $offset;
	${idPrefix}pageId = 'editCurriculum';
	${idPrefix}token = "$token";
	${idPrefix}rowCount = $rowCount;
	\$("#${idPrefix}addRecord").on("mouseover",function(){
	    \$( this ).css("background-color","red")
	});
	\$("#${idPrefix}addRecord").on("mouseout",function(){
	    \$( this ).css("background-color","white")
	});
	function ${idPrefix}SLonloadHandler() {
		console.log('in scrolling list onload handler');
		//keepAlive = window.setInterval("keepAlive()",2000);
		${idPrefix}updateList(${idPrefix}offset,${idPrefix}rowCount);
	}
	function ${idPrefix}addRecordClicked(div) {
		console.log('in the add record routine');
	}
	function ${idPrefix}editRecordClicked(div) {
		console.log('in the edit record routine');
		\$("#${idPrefix}form").toggle();
	}
	function ${idPrefix}updateList(offset, rowCount) {
		iOffset = ${idPrefix}offset;
		iRowCount = ${idPrefix}rowCount;
		setStatusMessage('contacted server - waiting . . .');
		xmlHttp = get_xmlHttp();
		xmlHttp.onreadystatechange = function() {
		if(xmlHttp.readyState==4) {
			var text_out;
			var display = "";
			xmlHttp.responseText;
			xmlReturn = xmlHttp.responseText;
			if (window.DOMParser) {
				parser = new DOMParser();
				//xmlDoc = parser.parseFromString(xmlReturn,"text/xml");
			} else { // Internet explorer
				xmlDoc=new ActiveXObject("Microsoft.XMLDOM");
				xmlDoc.async="false";
				xmlDoc.loadXML(xmlReturn);
			}
			\$("#statusMessage").html('retrieved users');
			//$("#statusMessage").html(xmlReturn);
			//console.log(xmlReturn + ' <<<--- XML return there');
			try {
				item_obj = JSON.parse(xmlReturn);
			}
			catch(err) {
				console.log(xmlReturn);
			}
			output = '';
			var rowClass = 'tableRow';
			//console.log (item_obj[0]);
			for (var itemNum = 0; itemNum < item_obj.length; itemNum++) {
				item = item_obj[itemNum];
				output += '<div class="' + rowClass + '" onclick="tableRowClicked(this)" itemindex="' + itemNum +'">';
				output += item.${fieldName} + ' ';
				output += '</div>'; 
				rowClass = rowClass == 'tableRowAlt'?'tableRow':'tableRowAlt';
			}
			document.getElementById("scroller").innerHTML = output;

			// timedMsg();     
		}
		}
		var serialized = '&offset=' + iOffset + '&rowCount=' + iRowCount + '&tempqueryid=' + ${idPrefix}tempQueryId;
		xmlHttp.open("GET", "${url}" + serialized,true);
		xmlHttp.send(null);
	
	}
	
			function prevClicked(divClicked)  {
				if (offset > 99) {
					offset = offset - 99;
				} else {
					offset = 0;
				}
				updateList(offset,rowCount);
			}
			function nextClicked(divClicked) {
				offset = offset += 99;
				updateList(offset,rowCount);
			}
			function retrieveChildren() {
			    console.log('retrieving children');
			}
			function tableRowClicked(divClicked) {
				if (currentSelected) {
					currentSelected.style.color = 'black';
				}
				var i = divClicked.getAttribute("userindex");
				divClicked.style.color = "red";
				currentSelected = divClicked;
				console.log(divClicked);
				selected_index = i;
				item = item_obj[i];
				//for (var fieldName in item) {
				//	\$("#${idPrefix}form").("[name*=" + fieldName + "]").val = item[fieldName];
				//}
				retrieveChildren();
				console.log(divClicked);
				console.log('table row clicked');
			}
			function searchChanged(inputField) {
				console.log(inputField.value + ' is the input value');
				updateOffset(inputField.value);
				console.log('search changed');
			}

		</script>
~;
	$tableHash{'javaScript'} = $jsOut;
	
	return(\%tableHash);
}
sub temp_query {
	my ($r) = @_;
	my $profile = &Apache::Promse::get_user_profile($Apache::Promse::env{'user_id'});
	my $temp_query_id = $r->param('tempqueryid');
	my $qry = "SELECT query FROM temp_queries WHERE query_id = ?";
	my $rst = $env{'dbh'}->prepare($qry);
	my @records;
	my $district_id = $$profile{'district_id'};
	my $subject = $$profile{'subject'};
	$rst->execute($temp_query_id);
	my $row = $rst->fetchrow_hashref();
	my $query = $$row{'query'};
	print STDERR "\n $query \n";
	print STDERR "\n $subject is subject $district_id is district id \n";
	$rst = $env{'dbh'}->prepare($query);
	$rst->execute($district_id, $subject);
	while (my $row = $rst->fetchrow_hashref()) {
	    push @records,{%$row};
	}
	$r->print(JSON::XS::->new->pretty(1)->encode( \@records));
}
sub handler {
    my $r = new CGI;
    &Apache::Promse::validate_user($r);
    if (($env{'username'} eq 'not_found') || !($env{'token'}=~/[^\s]/)){
        &Apache::Promse::top_of_page($r);
        &Apache::Promse::user_not_valid($r);
    } else {
        my $auth_token = &Apache::Promse::authenticate('Editor',$env{'token'});
        my $target;
        if ($r->param('target')) {
            $target = $r->param('target');
        } else {
            $target = '';
        }
        # my $validate = &Apache::Promse::validate_user($r);
        if ($auth_token ne 'ok') {
            &Apache::Promse::top_of_page_menus($r);
            &Apache::Promse::user_not_valid($r);
            &Apache::Promse::footer;
        } elsif ($r->param('action') eq 'ajax') {
			
			my $call = $r->param('call');
			if ($call eq 'getcurricula') {
				&get_curriculum_selector($r);
			} elsif ($call eq 'tempquery'){
				&temp_query($r);
			}
        } else {
            &Apache::Promse::top_of_page_menus($r,'editor',&editor_tabs_menu($r));
            # &Apache::Promse::editor_menu($r);
            # &editor_tabs_menu($r);
            if ($env{'menu'} eq 'home') {
                &Apache::Promse::current_messages($r);
            } elsif ($env{'menu'} eq 'resources') {
                if ($env{'action'} eq 'upload') {
                    &Apache::Promse::save_resource($r);
                }
                if ($env{'action'}  eq 'makefave') {
                    &Apache::Promse::save_fave($r);
                    &Apache::Promse::resource_box($r);
                } elsif ($env{'action'} eq 'removefave' ) {
                    &Apache::Promse::delete_fave($r);
                    &Apache::Promse::resource_box($r);
                }  
                if ($env{'action'} eq 'update') {
                    &Apache::Promse::update_resource($r);
                }
                if ($env{'action'} eq 'addtag') {
                    # addtag is a misnomer, should be change or toggle tag
                    &Apache::Promse::toggle_res_framework($r);
                    #&Apache::Promse::edit_resource_menu($r);
                    &Apache::Promse::framework_selector($r,'math');
                    # &Apache::Promse::resource_box($r);
                } elsif ($env{'action'} eq 'showvidslide' ) {
                    &Apache::Flash::vid_slide_html($r);
                } elsif ($env{'action'} eq 'view' ) {
                    &Apache::Promse::view_edit_resource($r);
                } elsif ($env{'action'} eq 'delete' ) {
                    &Apache::Promse::delete_resource($r);
                    &Apache::Promse::resource_box($r);
                } else {
                    if ($env{'submenu'} eq 'add') {
                        &Apache::Promse::upload_resource_form($r);
                    } elsif ($env{'submenu'} eq 'edit') {
                        &Apache::Promse::edit_resource($r);
                    } elsif ($env{'submenu'} eq 'categories') {
                        &Apache::Promse::edit_resource_categories($r);
                    } elsif ($env{'submenu'} eq 'tags') {
                        &Apache::Promse::framework_selector($r,'math');
                    } else {
                        # &Apache::Promse::resource_menu($r);
                        &Apache::Promse::resource_box($r);
                    }
                }
            } elsif ($env{'menu'} eq 'curriculum') {
				&edit_curriculum($r);
			} elsif ($env{'menu'} eq 'oldcurriculum') {
                &Apache::Flash::curriculum_coherence_html($r);
            } elsif ($env{'menu'} eq 'code') {
                &Apache::Flash::promse_admin_code_html($r);
            } elsif ($target eq 'video') {
                if ($env{'action'} eq 'saveclip') {
                    &Apache::Promse::save_clip($r);
                    &Apache::Promse::resource_box($r);
                } else { 
                    &Apache::Promse::video($r);
                }
            } elsif ($target eq 'keyword') {
                &Apache::Promse::keyword($r);
            } elsif ($env{'menu'} eq 'courses') { 
                &Apache::Promse::mini_course($r);
            } else {
                &Apache::Promse::current_messages($r);
            }
        }
    }
	if ($r->param('action') ne 'ajax') {
    	&Apache::Promse::footer;
	}
}
1;