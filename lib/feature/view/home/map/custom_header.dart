import 'package:flutter/material.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/feature/view/profile/profile_screen.dart';

class CustomHeader extends StatelessWidget {
  const CustomHeader({
    super.key,
    required this.mapOPTController,
  });

  final MapOPTController mapOPTController;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      left: 0,
      child: Obx(() {
        final userController = Get.find<UserController>();

        final user = userController.userModel.value?.userProfile;
        final profileImage =
            user?.image?.filename ?? Assets.images.defaultImage.path;

        return Padding(
          padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22.r),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(22.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 44.r,
                            height: 44.r,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xffE6E6E6),
                                width: 1,
                              ),
                            ),
                            child: ClipOval(
                              child: GestureDetector(
                                onTap: () {
                                  Get.to(ProfileScreen());
                                },
                                child: Image.network(
                                  '${ApiUrls.imageBaseUrl}$profileImage',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset(
                                      Assets.images.profileImage.path,
                                      fit: BoxFit.cover,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                Get.toNamed(AppRoutes.notificationScreen),
                            child: Container(
                              width: 40.r,
                              height: 40.r,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE9F8EE),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: SvgPicture.asset(
                                Assets.images.bell,
                                width: 20.w,
                                height: 20.h,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          SvgPicture.asset(
                            Assets.images.greenPin,
                            width: 18.w,
                            height: 18.h,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              mapOPTController.currentLocation.value,
                              style: TextStyle(
                                fontSize: 13.sp,
                                color: Colors.black,
                                fontWeight: FontWeight.w600,
                                fontFamily: FontFamily.poppins,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
