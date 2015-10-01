package Apache::Design;
# File: Apache/Admin.pm 
use CGI;
use Apache::Promse;
use strict;
sub top_of_page {
    my ($r) = @_;
    my $output = q~
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
    <html lang="en" xml:lang="en">
    <!-- Above is the Doctype for strict xhtml -->
    <head>
    <!-- Unicode encoding -->
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <title>PROMSE</title>
    <meta name="description" content="PROM/SE - Promoting rigorous outcomes in K-12 mathematics and science education" />
    <meta name="keywords" content="prom/se, PROM/SE, promse, PROMSE, K-12, K-12 mathematics, K-12 science, K-12 education, math, science" />
    <!-- Use the import to use more sophisticated css. Lower browsers (less then 5.0) do not process the import instruction, will default to structural markup -->
    <style type="text/css" media="all">@import "../_stylesheets/advanced.css";</style>
    <script src="../_scripts/general.js" type="text/javascript" charset="utf-8"></script>
    <SCRIPT language="JavaScript">
    //Redirect if Mac IE
    if (navigator.appVersion.indexOf("Mac")!=-1 && navigator.appName.substring(0,9) == "Microsoft") {
    	window.location="mac_ie_note.html";
    }
    if (document.images)
    {
      pic1= new Image(228,37);
      pic1.src="../_images/Homepage/QuestionOfTheMonthBot_over.gif";
      pic2= new Image(228,37);
      pic2.src="../_images/Homepage/VPDOBot_over.gif";
      pic3= new Image(42,41);
      pic3.src="../_images/Logo_NSF_over.gif";
      pic4= new Image(34,41);
      pic4.src="../_images/Logo_SMART_over.gif";
      pic5= new Image(25,41);
      pic5.src="../_images/Logo_HighAIMS_over.gif";
      pic6= new Image(76,41);
      pic6.src="../_images/Logo_InghamISD_over.gif";
      pic7= new Image(53,41);
      pic7.src="../_images/Logo_CalhounISD_over.gif";
      pic8= new Image(41,41);
      pic8.src="../_images/Logo_StClair_over.gif";
      pic9= new Image(115,41);
      pic9.src="../_images/Logo_MSU_over.gif";
      pic10= new Image(165,56);
      pic10.src="../_images/Internal_pages/RtNav_QuestionMonthAd_over.jpg";
      pic11= new Image(165,56);
      pic11.src="../_images/Internal_pages/RtNav_WhatsNewAd_over.jpg";
    }
    </SCRIPT>
    </head>
    ~;
    $r->print($output);
    $output = q~
    <body id="MS" onload="onloadFunctions('Home','NULL');">
    <div id="wrapper">
	<div id="wrapperNavLogoBar">
        <div id="barTop">
       <h3 id="skip"></h3>
		<span class="noShow">PROM/SE: Promoting Rigorous Outcomes in Mathematics and Science Education</span>
        </div>
            <div id="barContent">
            <ul id="navPersistent">
            <li id="liNavHome"><a href="default.html" id="navHome" title="Home">Home</a></li>
            <li id="liNavParents"><a href="#" id="navParents" title="Parents">Parents</a></li>
            <li id="liNavTA"><a href="teachers_associates/how_can_PROMSE_help.html" id="navTA" title="Teachers &amp; Associates">Teachers &amp; Associates <img src="../_images/BannerDnArrow.gif" width="7" height="4" alt="" /></a>
                <ul>
                <li><a href="teachers_associates/how_can_PROMSE_help.html" title="Teachers &amp; Associates: How can PROM/SE help me?">How can PROM/SE help me?</a></li>
                <li><a href="teachers_associates/role.html" title="Teachers &amp; Associates: The Role of PROM/SE Associates">The Role of PROM/SE Associates</a></li>
                <li><a href="teachers_associates/meet_associate.html" title="Teachers &amp; Associates: Meet an Associate">Meet an Associate</a></li>
                <li><a href="teachers_associates/FAQs.html" title="Teachers &amp; Associates: Frequently Asked Questions">Frequently Asked Questions</a></li>
                <li class="liLast"><a href="teachers_associates/login.html" title="Teachers &amp; Associates: Login">Login</a></li>
                </ul>
            </li>
            <li id="liNavProfessional"><a href="#" id="navProfessional" title="Professional Development">Mentors <img src="../_images/BannerDnArrow.gif" width="7" height="4" alt="" /></a> </li>
            <li id="liNavResearch"><a href="research_results/research_results.html" id="navResearch" title="Research &amp; Results">Research &amp; Results</a></li>
            <li id="liNavResources" class="liLast"><a href="resources/resources.html" id="navResources" title="Resources">Resources</a></li>
            </ul>
            </div>
            <div id="barBottom">
            <img src="../_images/BannerBot.jpg" width="770" height="12" alt="" />
            </div>
        <div id="barSecondary">
            <ul id="navTools">
            <li id="navToolsFirst"><a href="sitemap.html" id="navSiteMap" title="Sitemap">Sitemap</a> </li>
            <li><a href="contact.html" id="navContactUs" title="Contact Us">Contact Us</a></li>
            </ul>
            <div id="barSecondaryBottom"></div>
        </div>
    </div>
    ~;
    $r->print ($output);
    $r->print('<table><tr><td><table width="100%" border="0" cellspacing="0" cellpadding="10">');
    my $screen = 'home';
    my $token;
    &Apache::Promse::sidebar_options($screen, $token, $r); # just a bunch of rows
    $r->print ('<tr> <td align="center" valign="top" class="sidebar"><p><a href="http://www.oai.org/SMART/" target="_blank">');
    $r->print('<br></td></tr></table></td><td width="95%" align="left" valign="top">');    
    return 'ok';
}

sub default {
    # This is the original template page with no changes.
    my ($r) = @_;
    my $output = q~
    
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html lang="en" xml:lang="en">
<!-- Above is the Doctype for strict xhtml -->
<head>
<!-- Unicode encoding -->
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />

<title>PROMSE</title>
<meta name="description" content="PROM/SE - Promoting rigorous outcomes in K-12 mathematics and science education" />
<meta name="keywords" content="prom/se, PROM/SE, promse, PROMSE, K-12, K-12 mathematics, K-12 science, K-12 education, math, science" />
<!-- Use the import to use more sophisticated css. Lower browsers (less then 5.0) do not process the import instruction, will default to structural markup -->
<style type="text/css" media="all">@import "../_stylesheets/advanced.css";</style>
<script src="../_scripts/general.js" type="text/javascript" charset="utf-8"></script>
<SCRIPT language="JavaScript">
//Redirect if Mac IE
if (navigator.appVersion.indexOf("Mac")!=-1 && navigator.appName.substring(0,9) == "Microsoft") {
	window.location="mac_ie_note.html";
}
if (document.images)
{
  pic1= new Image(228,37);
  pic1.src="../_images/Homepage/QuestionOfTheMonthBot_over.gif";

  pic2= new Image(228,37);
  pic2.src="../_images/Homepage/VPDOBot_over.gif";

  pic3= new Image(42,41);
  pic3.src="../_images/Logo_NSF_over.gif";

  pic4= new Image(34,41);
  pic4.src="../_images/Logo_SMART_over.gif";

  pic5= new Image(25,41);
  pic5.src="../_images/Logo_HighAIMS_over.gif";

  pic6= new Image(76,41);
  pic6.src="../_images/Logo_InghamISD_over.gif";

  pic7= new Image(53,41);
  pic7.src="../_images/Logo_CalhounISD_over.gif";

  pic8= new Image(41,41);
  pic8.src="../_images/Logo_StClair_over.gif";

  pic9= new Image(115,41);
  pic9.src="../_images/Logo_MSU_over.gif";
 
  pic10= new Image(165,56);
  pic10.src="../_images/Internal_pages/RtNav_QuestionMonthAd_over.jpg";

  pic11= new Image(165,56);
  pic11.src="../_images/Internal_pages/RtNav_WhatsNewAd_over.jpg";
}
</SCRIPT>
</head>

<body id="MS" onload="onloadFunctions('Home','NULL');">
<div id="wrapper">
	<div id="wrapperNavLogoBar">
        <div id="barTop">
       <h3 id="skip"><a href="#content" tabindex="1" accesskey="2" title="Skip over the navigation to the content">[Skip to Content]</a></h3>
		<span class="noShow">PROM/SE: Promoting Rigorous Outcomes in Mathematics and Science Education</span>
        </div>
            <div id="barContent">
            <ul id="navPersistent">
            <li id="liNavHome"><a href="default.html" id="navHome" title="Home">Home</a></li>
            <li id="liNavOverview"><a href="overview/math_science_partnership.html" id="navOverview" title="PROM/SE Overview">Overview <img src="../_images/BannerDnArrow.gif" width="7" height="4" alt="" /></a>
                <ul>
                <li><a href="overview/math_science_partnership.html" title="PROM/SE Overview:What is a Math and Science Partnership?">What is a Math and Science Partnership?</a></li>
	            <li><a href="overview/mission.html" title="PROM/SE Overview: PROMSE Mission">PROMSE Mission</a></li>
                <li><a href="overview/goals.html" title="PROM/SE Overview: Our Goals">Our Goals</a></li>
	            <li><a href="overview/timeline_process.html" title="PROM/SE Overview: Timeline and Process">Timeline and Process</a></li>
	            <li><a href="overview/news.html" title="PROM/SE Overview: News and Outreach">News and Outreach</a></li>
                <li><a href="overview/partners.html" title="PROM/SE Overview: Partners">Partners</a></li>
                <li><a href="overview/NAC.html" title="PROM/SE Overview: National Advisory Committee">National Advisory Committee</a></li>
                <li class="liLast"><a href="overview/staff.html" title="PROM/SE Overview: Staff">Staff</a></li>
                </ul>
            </li>
            <li id="liNavParents"><a href="#" id="navParents" title="Parents">Parents</a></li>
            <li id="liNavTA"><a href="teachers_associates/how_can_PROMSE_help.html" id="navTA" title="Teachers &amp; Associates">Teachers &amp; Associates <img src="../_images/BannerDnArrow.gif" width="7" height="4" alt="" /></a>
                <ul>
                <li><a href="teachers_associates/how_can_PROMSE_help.html" title="Teachers &amp; Associates: How can PROM/SE help me?">How can PROM/SE help me?</a></li>
                <li><a href="teachers_associates/role.html" title="Teachers &amp; Associates: The Role of PROM/SE Associates">The Role of PROM/SE Associates</a></li>
                <li><a href="teachers_associates/meet_associate.html" title="Teachers &amp; Associates: Meet an Associate">Meet an Associate</a></li>
                <li><a href="teachers_associates/FAQs.html" title="Teachers &amp; Associates: Frequently Asked Questions">Frequently Asked Questions</a></li>
                <li class="liLast"><a href="teachers_associates/login.html" title="Teachers &amp; Associates: Login">Login</a></li>
                </ul>
            </li>
            <li id="liNavProfessional"><a href="#" id="navProfessional" title="Professional Development">Professional Development <img src="../_images/BannerDnArrow.gif" width="7" height="4" alt="" /></a> </li>
            <li id="liNavResearch"><a href="research_results/research_results.html" id="navResearch" title="Research &amp; Results">Research &amp; Results</a></li>
            <li id="liNavResources" class="liLast"><a href="resources/resources.html" id="navResources" title="Resources">Resources</a></li>
            </ul>
            </div>
            <div id="barBottom">
            <img src="../_images/BannerBot.jpg" width="770" height="12" alt="" />
            </div>
        <div id="barSecondary">
            <ul id="navTools">
            <li id="navToolsFirst"><a href="sitemap.html" id="navSiteMap" title="Sitemap">Sitemap</a> </li>
            <li><a href="contact.html" id="navContactUs" title="Contact Us">Contact Us</a></li>
            </ul>
            <div id="barSecondaryBottom"></div>
        </div>
    </div>
    <div id="wrapperColumn">
        <div id="mainColumn"><a name="content"></a>
            <div id="homeIntroSection">
            <dl id="homeIntroSectionMenu">
            <dt id="dtWhatWeDo"><a href="#" title="What We Do" onclick="toggleHomeIntro('WhatWeDo', 'WhoWeAre','OurPartners')" class="active">What We Do</a></dt>
          <dd id="ddWhatWeDo">
 			<p>
             PROM/SE is a comprehensive research and development effort to improve mathematics and science teaching and learning in grades K-12, based on assessment of students and teachers, improvement of standards and frameworks, and preparation and professional development of teachers.
            </p>
		  </dd>
            <dt id="dtWhoWeAre"><a href="#" title="Who We Are" onclick="toggleHomeIntro('WhoWeAre', 'WhatWeDo','OurPartners')">Who We Are</a></dt>
          <dd id="ddWhoWeAre">	
			<p>National Science Foundation-funded cooperative partnership.</p>
			<p>Six partnerships in Michigan and Ohio involving:</p>
			<ul>
			  <li>65 school districts</li>
			  <li>1200 PROM/SE associates</li>
			  <li>5000 inservice teachers</li>
			  <li>800 preservice teachers</li>
			  <li>350,000 K-12 students</li>
			</ul>
			<p>Project dates 2003-2008.</p>
		  </dd>
            <dt id="dtOurPartners"><a href="#" title="Our Partners" onclick="toggleHomeIntro('OurPartners', 'WhatWeDo','WhoWeAre')">Our Partners</a></dt>
          <dd id="ddOurPartners">
			<h4><a href="overview/partners.html#SMART" title="SMART Consortium">SMART Consortium</a></h4>
			<p>24 school districts in greater Cleveland, OH</p>
			<h4><a href="overview/partners.html#AIMS" title="High AIMS Consortium">High AIMS Consortium</a></h4>
			<p>12 school districts in greater Cincinnati, OH</p>
			<h4><a href="overview/partners.html#Ingham" title="Ingham County Intermediate School District">Ingham County Intermediate School District</a></h4>
			<p>10 school districts in greater Lansing, MI</p>
			<h4><a href="overview/partners.html#Calhoun" title="Calhoun County, MI Intermediate School District">Calhoun County, MI Intermediate School District</a></h4>
			<p>12 school districts</p>
			<h4><a href="overview/partners.html#StCliar" title="St. Clair County RESA">St. Clair County RESA</a></h4>
			<p>7 school districts</p>
			<h4><a href="overview/partners.html#MSU" title="Michigan State University">Michigan State University</a></h4>
		  </dd>
            </dl>
             </div>
            <div id="homeLinkContainer">
            <img src="../_images/Homepage/QuestionOfTheMonthTop.jpg" width="228" height="70" alt="Question of the Month" />
            <a href="#" title="Question of the Month"><span>Question of the Month</span></a>
            </div>
            <div id="homeLinkContainer2">
            <img src="../_images/Homepage/VPDOTop.jpg" width="228" height="70" alt="Virtual Professional Development Opportunities" />
            <a href="#" title="Virtual Professional Development Opportunities"><span>Virtual Professional Development Opportunities</span></a>
            </div>
        </div>
        <div id="sidebarColumn" >
            <div id="homeWhatsNew">
            <ul>
                <li><a href="overview/news_whats_new.html#NewOffices" title="PROM/SE Moves to New Offices">PROM/SE Moves to New Offices</a></li>
                <li><a href="overview/news_whats_new.html#NSFVisit" title="NSF Site Visit for June 1-3">NSF Site Visit for June 1-3</a></li>
                <li><a href="overview/news_whats_new.html#WebSiteGrowing" title="Our Website is Growing">Our Website is Growing</a></li>
                <li><a href="overview/news_whats_new.html#Summit" title="March District Contact Summit">March District Contact Summit</a></li>
                <li><a href="overview/news_whats_new.html#Institute" title="Spring Mathematics Associates Institute">Spring Mathematics Associates Institute</a></li>
             </ul>
             </div>
            <div id="homeCalendar">
            <h3>Calendar of Events</h3>
            <div id="tableContainer">
            <table>
            <tr>
            <th>Date</th>
            <th>Event</th>
            </tr>
            <tr>
            <td>April 26-27</td>
            <td><a href="#" title="SMART Spring Math Institute">SMART Spring Math Institute</a></td>
            </tr>
            <tr class="rowAlternate">
            <td>April 26</td>
            <td>Steering Committee teleconference</td>
            </tr>
            <tr>
            <td>May 5</td>
            <td>Executive Management Committee</td>
            </tr>
            <tr class="rowAlternate">
            <td>May 5</td>
            <td>District Contact Summit, Bowling Green, OH</td>
            </tr>

            <tr>
            <td>May 23</td>
            <td>High AIMS Science Assoc. Orientation, Cincinnati</td>
            </tr>

            <tr class="rowAlternate">
            <td>May 24</td>
            <td>Ingham/Calhoun Science Assoc. Orientation, Olivet, MI</td>
            </tr>

            <tr>
            <td>May 24</td>
            <td>Executive Management Committee, East Lansing</td>
            </tr>

            <tr class="rowAlternate">
            <td>May 25</td>
            <td>St. Clair Science Assoc. Orientation, Marysville, MI</td>
            </tr>

            <tr>
            <td>May 26</td>
            <td> SMART Science Assoc. Orientation, Cleveland, OH</td>
            </tr>

            <tr class="rowAlternate">
            <td>June 1-3</td>
            <td>NSF site visit</td>
            </tr>

            <tr>
            <td>June 28</td>
            <td>Executive Management Committee
            </td>
            </tr>

            <tr class="rowAlternate">
            <td>July 11-15</td>
            <td>LessonLab Facilitator Training
            </td>
            </tr>

            <tr>
            <td>August 1-5</td>
            <td>Summer Math Academy, Okemos, MI
            </td>
            </tr>

            <tr class="rowAlternate">
            <td>August 8-10</td>
            <td>Summer Math Academy, Cincinnati area
            </td>
            </tr>

            <tr>
            <td>August 10-12</td>
            <td>Summer Math Academy, Cleveland area
            </td>
            </tr>
            <tr class="bottomRow">
            <td colspan="2">
            </td>
            </tr>
            </table>
            </div>
            </div>
        </div>
    </div>
	    <div id="wrapperFooter">
        <div>
        <hr />
        <ul id="footerPartnerList">
        <li id="footerLiNSF"><a href="overview/partners.html#NSF" title="National Science Foundation"><span>National Science Foundation</span></a></li>
        <li id="footerLiSMART"><a href="overview/partners.html#SMART" title="SMART Consortium"><span>SMART Consortium</span></a></li>
        <li id="footerLiAIMS"><a href="overview/partners.html#AIMS" title="High AIMS Consortium"><span>High AIMS Consortium</span></a></li>
        <li id="footerLiIngham"><a href="overview/partners.html#Ingham" title="Ingham County Intermediate School District"><span>Ingham County Intermediate School District</span></a></li>
        <li id="footerLiCalhoun"><a href="overview/partners.html#Calhoun" title="Calhoun County Intermediate School District"><span>Calhoun County Intermediate School District</span></a></li>
        <li id="footerLiStClair"><a href="overview/partners.html#StClair" title="St. Clair County Regional Educational Service Agency"><span>St. Clair County Regional Educational Service Agency</span></a></li>
        <li id="footerLiMSU"><a href="overview/partners.html#MSU" title="MSU PROM/SE Project"><span>MSU PROM/SE Project</span></a></li>
        <li id="footerLiMSUInfo">© MSU PROM/SE Project, Michigan State University, 236 Erickson Hall, East Lansing, MI 48824, phone 517/353-4884, fax 517/432-0132.</li>
        </ul>
        <p>
        www.promse.msu.edu. PROM/SE is funded by the National Science Foundation under Cooperative Agreement Grant No. EHR-0314866.
        </p>
        </div>
    </div>
</div>
</body>
</html>
~;
$r->print($output);
return 'ok';
}
1;