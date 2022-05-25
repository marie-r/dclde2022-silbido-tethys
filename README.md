# DCLDE 2022 Silbido to Tethys

These subroutines can be used to convert information about DCLDE 2022 
deployments and associated detections with the software package *silbido* 
to XML documents that can be ingested by Tethys.

For information about *silbido* see:

- Roch, M. A., Brandes, T. S., Patel, B., Barkley, Y., Baumann-Pickering, S. and Soldevilla, M. S. (2011). Automated extraction of odontocete whistle contours. *Journal of the Acoustical Society of America *130, 2212-23, doi:10.1121/1.3624821.

- Li, P., Liu, X., Palmer, K. J., Fleishman, E., Gillespie, D., Nosal, E.-M., Shiu , Y., Klinck, H., Cholewiak, D., Helble, T. et al. (2020). Learning Deep Models from Synthetic Data for Extracting Dolphin Whistle Contours. In *Intl. Joint Conf. Neural Net.*, pp. 10. Glasgow, Scotland.

For information about Tethys, see the Tethys web site[Tethys Metadata](https://tethys.sdsu.edu) or
- Roch, M. A., Baumann-Pickering, S., Batchelor, H., Hwang, D., Sirovic, A., Hildebrand, J. A., Berchok, C. L., Cholewiak, D., Munger, L. M., Oleson, E. M. et al. (2013). Tethys: a workbench and database for passive acoustic metadata. *Oceans* 2013, 5 pp.
- Roch, M. A., Batchelor, H., Baumann-Pickering, S., Berchock, C. L., Cholewiak, D., Fujioka, E., Garland , E. C., Herbert, S., Hildebrand, J. A., Oleson, E. M. et al. (2016). Management of acoustic metadata for bioacoustics. *Ecological Informatics* 31, 122-136, doi:http://dx.doi.org/10.1016/j.ecoinf.2015.12.002.


# Requirements
This code requires a recent version of Matlab, and Tethys's Nilus XML generator
(Tethys version 3.0).  In addition, it is assumed that the DCLDE metadata 
spreadsheets are available and that *silbido* has been used to create
a set of annotation (detection) files.

There are a couple of hard-coded pathnames that will need to be adjusted
prior to using this code.  These are in dclde_deployments2xml.m and dclde_process_detections.m 
and are described in more detail below.

# Usage

The function **dclde_deployments2xml** will create a set of deployment records suitable
for use in Tethys.  As the R/V Lasker and R/V Sette data have gaps in their records, 
these are broken up into mulitple deployments.  We also downsample the array
GPS information to one sample per minute.  For localization, this is not ideal,
but it significantly reduces the size of the GPS data that are stored in Tehtys 
and increases efficiency for most tasks.  Note that we used a different version
of the GPS than the one distributed with the data set, if you do not have access
to this, change the variable complete_gps to false.

Function **dclde_process_detections** assumes that the detections
are stored relative to the direcotry named in variable base_dir.
Subdirectories 1705 and 1706 representing the arrays used on the R/V 
Lasker and R/V Sette respectively should be present.   We group detections
into sets of detection efforts based on duration and gaps.  Any time there
is a gap in the detection efffort of a minute or more, we start a new
detection effort.  As encounters with lots of whistle activity and cause
the Java heap allocated by Matlab to exhaust itself, we also start new
efforts every two hours.  This does not affect the ability to represent
things in Tethys.

Both of these functions will create a set of XML files that can be
uploaded to Tethys using standard Tehtys upload techniques (see the
Tethys manual for details).

# Other
Several helper functions are included in this repository.
- dclde_detections2xml - Called by dclde_process_detections to generate the 
 XML files.
- binary_search - Fast sorted array searching
- createSubclass - Helper function to overcome Matlab limitation that does not
 allow creation of nested subclasses.
- effort-diel - Not yet used
- audit_gps - identified issues with GPS tracks


